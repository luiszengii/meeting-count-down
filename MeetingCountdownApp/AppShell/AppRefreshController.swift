import AppKit
import Combine
import Foundation

/// `AppRefreshController` 负责把“周期性重读本地系统日历”和“系统事件触发重读”收口到一起。
/// 它不决定如何读取会议，只负责在正确时机调用 `SourceCoordinator.refresh(trigger:)`。
@MainActor
final class AppRefreshController {
    /// 当前唯一的系统日历聚合入口。
    private let sourceCoordinator: SourceCoordinator
    /// 时钟入口，方便把“近会 30 秒刷新”判断写成可替换逻辑。
    private let dateProvider: any DateProviding
    /// 用于监听时区变化。
    private let notificationCenter: NotificationCenter
    /// 用于监听系统睡眠唤醒。
    private let workspaceNotificationCenter: NotificationCenter

    /// 观察 `SourceCoordinator.state`，用于每次状态变化后重排下一次周期刷新。
    private var sourceStateCancellable: AnyCancellable?
    /// 当前等待触发周期刷新的异步任务。
    private var scheduledRefreshTask: Task<Void, Never>?
    /// `NSWorkspace.didWakeNotification` 监听 token。
    private var didWakeObserver: NSObjectProtocol?
    /// `NSSystemTimeZoneDidChangeNotification` 监听 token。
    private var timezoneObserver: NSObjectProtocol?

    init(
        sourceCoordinator: SourceCoordinator,
        dateProvider: any DateProviding,
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.sourceCoordinator = sourceCoordinator
        self.dateProvider = dateProvider
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter

        bindState()
        registerWakeObserver()
        registerTimezoneObserver()
    }

    /// 每次 `SourceCoordinator` 状态变化后，都重新安排下一次周期刷新。
    private func bindState() {
        sourceStateCancellable = sourceCoordinator.$state.sink { [weak self] state in
            Task { @MainActor [weak self] in
                self?.scheduleNextRefresh(using: state)
            }
        }
    }

    /// 睡眠唤醒后立刻重读，减少计时器漂移和系统日历状态滞后。
    private func registerWakeObserver() {
        didWakeObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.sourceCoordinator.refresh(trigger: .wakeFromSleep)
            }
        }
    }

    /// 时区变化后立刻重算会议时间和刷新节奏。
    private func registerTimezoneObserver() {
        timezoneObserver = notificationCenter.addObserver(
            forName: NSNotification.Name.NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.sourceCoordinator.refresh(trigger: .timezoneChanged)
            }
        }
    }

    /// 根据当前下一场会议距离开始还有多久，决定下一次周期刷新的延迟。
    private func scheduleNextRefresh(using state: SourceCoordinatorState) {
        scheduledRefreshTask?.cancel()

        let delay = refreshInterval(for: state)

        scheduledRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            await self?.sourceCoordinator.refresh(trigger: .scheduledRefresh)
        }
    }

    /// 默认 120 秒刷新；如果下一场会议已进入 30 分钟窗口，就提升到 30 秒。
    private func refreshInterval(for state: SourceCoordinatorState) -> TimeInterval {
        guard let nextMeeting = state.nextMeeting else {
            return 120
        }

        let interval = nextMeeting.startAt.timeIntervalSince(dateProvider.now())
        return interval < 30 * 60 ? 30 : 120
    }
}
