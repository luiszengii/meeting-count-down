import Foundation

/// `AppRuntime` 负责把应用运行期需要长期持有的共享对象绑在一起。
/// 这里的价值不是再做一层业务状态，而是确保 `SourceCoordinator`
/// 和系统日历桥接控制器能够共享同一份偏好存储、EventKit 桥接和生命周期。
@MainActor
final class AppRuntime: ObservableObject {
    /// 主数据源协调层。
    let sourceCoordinator: SourceCoordinator
    /// CalDAV / 系统日历配置控制器。
    let systemCalendarConnectionController: SystemCalendarConnectionController
    /// 设置窗口控制器，负责记住 SwiftUI `Settings` scene 对应的真实 `NSWindow`。
    let settingsWindowController: SettingsWindowController

    init(
        sourceCoordinator: SourceCoordinator,
        systemCalendarConnectionController: SystemCalendarConnectionController,
        settingsWindowController: SettingsWindowController
    ) {
        self.sourceCoordinator = sourceCoordinator
        self.systemCalendarConnectionController = systemCalendarConnectionController
        self.settingsWindowController = settingsWindowController
    }
}
