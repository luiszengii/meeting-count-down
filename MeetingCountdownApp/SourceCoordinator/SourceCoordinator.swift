import Foundation
import SwiftUI

/// `SourceCoordinatorState` 是菜单栏应用当前最关键的聚合状态。
/// 它有意保持扁平：健康状态、最近刷新时间、下一场会议和最近错误。
/// 这样 UI 可以直接消费它，而不用知道底层到底经历了多少次刷新、权限检查或数据转换。
struct SourceCoordinatorState: Equatable, Sendable {
    /// 当前源整体健康度，会直接决定菜单栏短文案和设置页诊断信息。
    var healthState: SourceHealthState
    /// 最近一次成功刷新完成的时间。
    var lastRefreshAt: Date?
    /// 当前被选中的“下一场会议”，为空表示暂无可提醒会议。
    var nextMeeting: MeetingRecord?
    /// 最近一次刷新得到的规范化会议列表。
    var meetings: [MeetingRecord]
    /// 当前是否处于刷新中，供 UI 控制按钮禁用态。
    var isRefreshing: Bool
    /// 最近一次失败对应的用户可见错误文案。
    var lastErrorMessage: String?

    /// 构造应用启动后的初始状态。
    /// 这里故意把大多数字段清空，等真实刷新完成后再写入健康状态和会议数据。
    static func initial(sourceDisplayName: String, lastRefreshAt: Date? = nil) -> SourceCoordinatorState {
        SourceCoordinatorState(
            healthState: .unconfigured(message: "\(sourceDisplayName) 尚未完成接入"),
            lastRefreshAt: lastRefreshAt,
            nextMeeting: nil,
            meetings: [],
            isRefreshing: false,
            lastErrorMessage: nil
        )
    }

    /// 给 UI 提供最优先展示的一行文本。
    /// 如果已经有下一场会议，就优先展示会议标题；否则展示健康状态摘要。
    var primaryStatusLine: String {
        if let nextMeeting {
            return nextMeeting.title
        }

        return healthState.summary
    }
}

/// `SourceCoordinator` 是 Phase 0 的主状态机入口。
/// 当前产品已经收敛成 CalDAV 单一路径，因此它只协调一个 `MeetingSource`，
/// 所有刷新动作都统一走 `refresh(trigger:)`，避免 UI 或系统监听直接改聚合状态。
@MainActor
final class SourceCoordinator: ObservableObject {
    /// 这是整个菜单栏壳层最核心的公开状态，任何视图都应该只读它，而不是直接接触底层数据源。
    @Published private(set) var state: SourceCoordinatorState

    /// 当前唯一活动的数据源。
    private let source: any MeetingSource
    /// 独立注入选择器，确保“下一场会议规则”可单测、可替换。
    private let nextMeetingSelector: any NextMeetingSelecting
    /// 非敏感偏好持久化入口。
    /// 协调层需要读取它来应用会议过滤规则，并在成功刷新后落最近成功读取时间。
    private let preferencesStore: any PreferencesStore
    /// 独立注入时钟，避免业务层直接绑定真实时间。
    private let dateProvider: any DateProviding
    /// 统一日志入口，方便后续接入真实系统能力时保留可追踪记录。
    private let logger: AppLogger

    /// 初始化协调层，并可选择在启动时立即触发一次刷新。
    init(
        source: any MeetingSource,
        nextMeetingSelector: any NextMeetingSelecting,
        preferencesStore: any PreferencesStore,
        dateProvider: any DateProviding,
        logger: AppLogger,
        lastSuccessfulRefreshAt: Date? = nil,
        autoRefreshOnStart: Bool = true
    ) {
        self.source = source
        self.nextMeetingSelector = nextMeetingSelector
        self.preferencesStore = preferencesStore
        self.dateProvider = dateProvider
        self.logger = logger
        self.state = .initial(
            sourceDisplayName: source.descriptor.displayName,
            lastRefreshAt: lastSuccessfulRefreshAt
        )

        if autoRefreshOnStart {
            Task { [weak self] in
                await self?.refresh(trigger: .appLaunch)
            }
        }
    }

    /// 让菜单栏在空间极小的前提下优先显示最有价值的信息。
    /// 一旦已经算出下一场会议，就显示相对倒计时；否则回退到健康状态短标签。
    /// 菜单栏标题优先显示倒计时，否则退回到短健康标签。
    var menuBarTitle: String {
        if let nextMeeting = state.nextMeeting {
            return countdownLine(until: nextMeeting.startAt)
        }

        return state.healthState.shortLabel
    }

    /// 为菜单栏标题配套选择图标。
    /// 这里统一从聚合状态派生，避免 View 层自己再判断一遍业务条件。
    /// 菜单栏图标根据“是否已有下一场会议”切换。
    var menuBarSymbolName: String {
        if state.nextMeeting != nil {
            return "calendar.badge.clock"
        }

        return state.healthState.symbolName
    }

    /// 生成菜单栏详情文字。
    /// 优先级固定为：刷新中 > 错误 > 下一场会议开始时间 > 健康状态摘要。
    /// 菜单栏详情行统一表达当前最值得解释的状态。
    var detailLine: String {
        if state.isRefreshing {
            return "正在刷新 \(source.descriptor.displayName)"
        }

        if let errorMessage = state.lastErrorMessage {
            return errorMessage
        }

        if let nextMeeting = state.nextMeeting {
            return "将于 \(meetingStartLine(for: nextMeeting))"
        }

        return state.healthState.summary
    }

    /// 把最近刷新时间转换成可读字符串。
    /// 如果还没成功刷新过，就显式告诉用户“尚未刷新”，避免误以为界面卡住。
    /// 以绝对时间格式化最近一次刷新时间，便于用户确认系统是不是刚刚更新过。
    var lastRefreshLine: String {
        guard let lastRefreshAt = state.lastRefreshAt else {
            return "尚未刷新"
        }

        return Self.absoluteFormatter.string(from: lastRefreshAt)
    }

    /// 执行统一刷新入口。
    /// 所有刷新动作都从这里经过，这样日志、错误处理、状态切换和下一场会议重算都能保持一致。
    func refresh(trigger: RefreshTrigger) async {
        let now = dateProvider.now()
        state.isRefreshing = true
        state.lastErrorMessage = nil
        logger.info("Refreshing source \(source.descriptor.sourceIdentifier) because \(trigger.rawValue)")

        /// `defer` 保证无论刷新成功还是失败，最终都能把刷新中的标志位关掉。
        defer {
            state.isRefreshing = false
        }

        do {
            let snapshot = try await source.refresh(trigger: trigger, now: now)
            /// 先统一排序，再做“下一场会议”选择，避免底层源返回顺序不稳定。
            let sortedMeetings = snapshot.meetings.sorted(by: Self.sortMeetings)
            let reminderPreferences = await preferencesStore.loadReminderPreferences()

            state.healthState = snapshot.healthState
            state.lastRefreshAt = snapshot.refreshedAt
            state.meetings = sortedMeetings
            state.nextMeeting = nextMeetingSelector.selectNextMeeting(
                from: sortedMeetings,
                now: now,
                reminderPreferences: reminderPreferences
            )
            state.lastErrorMessage = nil
            try? await preferencesStore.saveLastSuccessfulRefreshAt(snapshot.refreshedAt)
            logger.info(
                "Refresh succeeded with \(sortedMeetings.count) meeting(s), health=\(snapshot.healthState.shortLabel), nextMeeting=\(state.nextMeeting?.id ?? "none")"
            )
        } catch let error as MeetingSourceError {
            switch error {
            case .notConfigured:
                state.healthState = .unconfigured(message: error.userFacingMessage)
            case .unavailable:
                state.healthState = .failed(message: error.userFacingMessage)
            }
            state.nextMeeting = nil
            state.meetings = []
            state.lastErrorMessage = error.userFacingMessage
            logger.error("Meeting source failed with domain error: \(error.userFacingMessage)")
        } catch {
            state.healthState = .failed(message: "刷新失败")
            state.nextMeeting = nil
            state.meetings = []
            state.lastErrorMessage = error.localizedDescription
            logger.error("Meeting source failed with unexpected error: \(error.localizedDescription)")
        }
    }

    /// 为 UI 生成“绝对开始时间 + 相对倒计时”的组合文本。
    func meetingStartLine(for meeting: MeetingRecord) -> String {
        "\(Self.absoluteFormatter.string(from: meeting.startAt)) (\(countdownLine(until: meeting.startAt)))"
    }

    /// 把目标开始时间转换成人类可读的倒计时标签。
    /// 这里故意在一分钟以内统一显示“即将开始”，避免秒级跳动导致菜单栏标题过于噪音。
    private func countdownLine(until date: Date) -> String {
        let interval = max(0, date.timeIntervalSince(dateProvider.now()))

        if interval < 60 {
            return "即将开始"
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll

        return formatter.string(from: interval) ?? "稍后开始"
    }

    /// 统一会议排序规则，供刷新后的列表排序和选择器前置整理复用。
    private static func sortMeetings(lhs: MeetingRecord, rhs: MeetingRecord) -> Bool {
        if lhs.startAt != rhs.startAt {
            return lhs.startAt < rhs.startAt
        }

        return lhs.id < rhs.id
    }

    /// 统一绝对时间格式，当前先只展示时分，后续再按设计扩展日期信息。
    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
