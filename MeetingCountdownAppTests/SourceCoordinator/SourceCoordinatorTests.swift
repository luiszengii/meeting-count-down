import Foundation
import XCTest
@testable import FeishuMeetingCountdown

/// 这些测试验证 Phase 0 聚合层的主状态流是否稳定。
@MainActor
final class SourceCoordinatorTests: XCTestCase {
    /// 验证刷新成功后，协调层会更新最近刷新时间，并重新计算下一场会议。
    func testRefreshUpdatesLastRefreshAndNextMeeting() async {
        let now = fixedNow()
        let coordinator = SourceCoordinator(
            source: StubMeetingSource(
                descriptor: descriptor(),
                currentHealthState: .ready(message: "系统日历已接入"),
                sampleMeetings: [
                    meeting(id: "later", now: now, offsetMinutes: 45),
                    meeting(id: "sooner", now: now, offsetMinutes: 15)
                ]
            ),
            nextMeetingSelector: DefaultNextMeetingSelector(),
            dateProvider: FixedDateProvider(currentDate: now),
            logger: AppLogger(source: "SourceCoordinatorTests"),
            autoRefreshOnStart: false
        )

        await coordinator.refresh(trigger: .manualRefresh)

        XCTAssertEqual(coordinator.state.lastRefreshAt, now)
        XCTAssertEqual(coordinator.state.nextMeeting?.id, "sooner")
        XCTAssertEqual(coordinator.state.healthState, .ready(message: "系统日历已接入"))
    }

    /// 验证刷新前后的菜单栏标题会根据下一场会议倒计时切换，而不是一直停留在健康状态短标签。
    func testMenuBarTitleSwitchesFromHealthLabelToCountdownAfterRefresh() async {
        let now = fixedNow()
        let coordinator = SourceCoordinator(
            source: StubMeetingSource(
                descriptor: descriptor(),
                currentHealthState: .ready(message: "系统日历已接入"),
                sampleMeetings: [meeting(id: "calendar", now: now, offsetMinutes: 40)]
            ),
            nextMeetingSelector: DefaultNextMeetingSelector(),
            dateProvider: FixedDateProvider(currentDate: now),
            logger: AppLogger(source: "SourceCoordinatorTests"),
            autoRefreshOnStart: false
        )

        XCTAssertEqual(coordinator.menuBarTitle, "未配置")

        await coordinator.refresh(trigger: .manualRefresh)

        XCTAssertEqual(coordinator.state.nextMeeting?.id, "calendar")
        XCTAssertNotEqual(coordinator.menuBarTitle, coordinator.state.healthState.shortLabel)
    }

    /// 验证没有下一场会议时，菜单栏基础图标会继续保留日历 / 倒计时语义，而不是退回看起来像设置入口的符号。
    func testMenuBarSymbolUsesCalendarOrTimerSemanticsInsteadOfSettingsSlider() async {
        let now = fixedNow()
        let coordinator = SourceCoordinator(
            source: StubMeetingSource(
                descriptor: descriptor(),
                currentHealthState: .ready(message: "系统日历已接入"),
                sampleMeetings: []
            ),
            nextMeetingSelector: DefaultNextMeetingSelector(),
            dateProvider: FixedDateProvider(currentDate: now),
            logger: AppLogger(source: "SourceCoordinatorTests"),
            autoRefreshOnStart: false
        )

        XCTAssertEqual(coordinator.menuBarSymbolName, "calendar.badge.exclamationmark")
        XCTAssertNotEqual(coordinator.menuBarSymbolName, "slider.horizontal.3")

        await coordinator.refresh(trigger: .manualRefresh)

        XCTAssertEqual(coordinator.menuBarSymbolName, "timer")
        XCTAssertNotEqual(coordinator.menuBarSymbolName, "slider.horizontal.3")
    }

    /// 验证底层源抛出真正不可用错误时，协调层会把状态标记为失败并清空会议结果。
    func testRefreshFailureMarksStateAsFailed() async {
        let now = fixedNow()
        let coordinator = SourceCoordinator(
            source: FailingMeetingSource(
                descriptor: descriptor(),
                error: .unavailable(message: "网络不可用")
            ),
            nextMeetingSelector: DefaultNextMeetingSelector(),
            dateProvider: FixedDateProvider(currentDate: now),
            logger: AppLogger(source: "SourceCoordinatorTests"),
            autoRefreshOnStart: false
        )

        await coordinator.refresh(trigger: .manualRefresh)

        XCTAssertEqual(coordinator.state.healthState, .failed(message: "网络不可用"))
        XCTAssertEqual(coordinator.state.lastErrorMessage, "网络不可用")
        XCTAssertNil(coordinator.state.nextMeeting)
    }

    /// 验证底层源抛出“尚未配置”时，协调层会保持未配置语义，而不是误判成失败。
    func testRefreshNotConfiguredKeepsStateAsUnconfigured() async {
        let now = fixedNow()
        let coordinator = SourceCoordinator(
            source: FailingMeetingSource(
                descriptor: descriptor(),
                error: .notConfigured(message: "尚未选择需要纳入提醒的系统日历")
            ),
            nextMeetingSelector: DefaultNextMeetingSelector(),
            dateProvider: FixedDateProvider(currentDate: now),
            logger: AppLogger(source: "SourceCoordinatorTests"),
            autoRefreshOnStart: false
        )

        await coordinator.refresh(trigger: .manualRefresh)

        XCTAssertEqual(coordinator.state.healthState, .unconfigured(message: "尚未选择需要纳入提醒的系统日历"))
        XCTAssertEqual(coordinator.state.lastErrorMessage, "尚未选择需要纳入提醒的系统日历")
        XCTAssertNil(coordinator.state.nextMeeting)
    }

    /// 统一生成测试用源描述符，避免每个测试都重复拼接样板字段。
    private func descriptor() -> MeetingSourceDescriptor {
        MeetingSourceDescriptor(
            sourceIdentifier: "test-system-calendar",
            displayName: "CalDAV / 系统日历"
        )
    }

    /// 构造在固定时间基础上偏移若干分钟的测试会议。
    private func meeting(id: String, now: Date, offsetMinutes: Int) -> MeetingRecord {
        let startAt = Calendar(identifier: .gregorian).date(byAdding: .minute, value: offsetMinutes, to: now)!
        let endAt = Calendar(identifier: .gregorian).date(byAdding: .minute, value: 30, to: startAt)!

        return MeetingRecord(
            id: id,
            title: "Meeting \(id)",
            startAt: startAt,
            endAt: endAt,
            source: descriptor()
        )
    }

    /// 返回所有测试共用的固定当前时间，确保断言稳定。
    private func fixedNow() -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 9, minute: 0))!
    }
}

/// 固定时钟实现，用于让测试里的“当前时间”完全可控。
private struct FixedDateProvider: DateProviding {
    /// 测试时注入的固定当前时间。
    let currentDate: Date

    /// 直接返回注入的固定时间。
    func now() -> Date {
        currentDate
    }
}

/// 故意失败的数据源实现，用于验证协调层错误处理路径。
private struct FailingMeetingSource: MeetingSource {
    /// 这个失败源也需要暴露来源描述，方便协调层照常记录模式信息。
    let descriptor: MeetingSourceDescriptor
    /// 预设要抛出的领域错误。
    let error: MeetingSourceError

    /// 失败源的健康状态直接映射到失败。
    func healthState() async -> SourceHealthState {
        .failed(message: error.userFacingMessage)
    }

    /// 每次刷新都抛出预设错误，便于稳定触发失败路径。
    func refresh(trigger: RefreshTrigger, now: Date) async throws -> SourceSyncSnapshot {
        throw error
    }
}
