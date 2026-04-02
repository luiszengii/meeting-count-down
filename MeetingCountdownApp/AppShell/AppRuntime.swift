import Foundation

/// `AppRuntime` 负责把应用运行期需要长期持有的共享对象绑在一起。
/// 这里的价值不是再做一层业务状态，而是确保 `SourceCoordinator`、提醒引擎
/// 和系统日历桥接控制器能够共享同一份偏好存储、时钟和生命周期。
@MainActor
final class AppRuntime: ObservableObject {
    /// 主数据源协调层。
    let sourceCoordinator: SourceCoordinator
    /// CalDAV / 系统日历配置控制器。
    let systemCalendarConnectionController: SystemCalendarConnectionController
    /// 当前唯一的本地提醒引擎。
    let reminderEngine: ReminderEngine
    /// 设置页使用的提醒偏好控制器。
    let reminderPreferencesController: ReminderPreferencesController
    /// 设置页使用的提醒音频库控制器。
    let soundProfileLibraryController: SoundProfileLibraryController
    /// 设置页使用的开机启动控制器。
    let launchAtLoginController: LaunchAtLoginController
    /// 设置窗口控制器，负责记住 SwiftUI `Settings` scene 对应的真实 `NSWindow`。
    let settingsWindowController: SettingsWindowController
    /// 菜单栏秒级倒计时和闪烁共用的展示时钟。
    let menuBarPresentationClock: MenuBarPresentationClock
    /// AppKit 状态栏控制器负责真正把菜单栏按钮和浮层安装到系统菜单栏。
    let menuBarStatusItemController: MenuBarStatusItemController
    /// 周期刷新与系统事件监听控制器。
    /// 这里不直接暴露给界面，只是通过 runtime 强持有它的生命周期。
    let appRefreshController: AppRefreshController

    init(
        sourceCoordinator: SourceCoordinator,
        systemCalendarConnectionController: SystemCalendarConnectionController,
        reminderEngine: ReminderEngine,
        reminderPreferencesController: ReminderPreferencesController,
        soundProfileLibraryController: SoundProfileLibraryController,
        launchAtLoginController: LaunchAtLoginController,
        settingsWindowController: SettingsWindowController,
        menuBarPresentationClock: MenuBarPresentationClock,
        menuBarStatusItemController: MenuBarStatusItemController,
        appRefreshController: AppRefreshController
    ) {
        self.sourceCoordinator = sourceCoordinator
        self.systemCalendarConnectionController = systemCalendarConnectionController
        self.reminderEngine = reminderEngine
        self.reminderPreferencesController = reminderPreferencesController
        self.soundProfileLibraryController = soundProfileLibraryController
        self.launchAtLoginController = launchAtLoginController
        self.settingsWindowController = settingsWindowController
        self.menuBarPresentationClock = menuBarPresentationClock
        self.menuBarStatusItemController = menuBarStatusItemController
        self.appRefreshController = appRefreshController
    }
}
