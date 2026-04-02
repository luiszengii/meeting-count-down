import Foundation

/// `MenuBarPresentationClock` 给菜单栏标签提供一个受控的当前时间。
/// 它只负责固定频率地发布 `now`，让菜单栏可以做秒级倒计时和闪烁；
/// 真正的会议刷新与提醒调度仍然由 `SourceCoordinator` 和 `ReminderEngine` 决定。
@MainActor
final class MenuBarPresentationClock: ObservableObject {
    /// 菜单栏当前应该拿来渲染的时间点。
    @Published private(set) var now: Date

    /// 持续驱动菜单栏秒级变化的主 actor 循环任务。
    private var tickTask: Task<Void, Never>?

    init(
        initialNow: Date = Date(),
        tickInterval: TimeInterval = 0.25
    ) {
        self.now = initialNow
        self.tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(tickInterval))
                } catch {
                    return
                }

                guard !Task.isCancelled else {
                    return
                }

                self?.now = Date()
            }
        }
    }

    deinit {
        tickTask?.cancel()
    }
}
