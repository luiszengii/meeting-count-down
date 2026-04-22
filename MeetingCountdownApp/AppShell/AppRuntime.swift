import Foundation

// MARK: - CoreRuntime

/// `CoreRuntime` 聚合所有与"业务状态机"直接相关的共享对象。
/// 这些对象处理会议数据读取、提醒调度和偏好持久化，不依赖 AppKit 壳层。
///
/// ## 边界说明
///
/// `CoreRuntime` 中的对象可以在没有 AppKit 界面的情况下独立运行和测试；
/// 它们不知道菜单栏、状态栏按钮或设置窗口的存在。
struct CoreRuntime {
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
    /// 菜单栏秒级倒计时和闪烁共用的展示时钟。
    let menuBarPresentationClock: MenuBarPresentationClock
}

// MARK: - ShellRuntime

/// `ShellRuntime` 聚合所有依赖 AppKit 壳层的共享控制器。
/// 这些对象负责把 `CoreRuntime` 里的业务状态映射成系统 UI，
/// 并在需要时向 `CoreRuntime` 反映用户操作。
///
/// ## 边界说明
///
/// `ShellRuntime` 中的对象假设在主线程 AppKit 上下文中运行；
/// 它们可以持有 NSWindow、NSStatusItem 等 AppKit 类型。
struct ShellRuntime {
    /// 开机启动控制器（SMAppService / launchd 桥接）。
    let launchAtLoginController: LaunchAtLoginController
    /// 设置窗口控制器，负责记住 SwiftUI `Settings` scene 对应的真实 `NSWindow`。
    let settingsWindowController: SettingsWindowController
    /// AppKit 状态栏控制器负责真正把菜单栏按钮和浮层安装到系统菜单栏。
    let menuBarStatusItemController: MenuBarStatusItemController
    /// 周期刷新与系统事件监听控制器。
    /// 这里不直接暴露给界面，只是通过 runtime 强持有它的生命周期。
    let appRefreshController: AppRefreshController
}

// MARK: - AppRuntime

/// `AppRuntime` 负责把应用运行期需要长期持有的共享对象绑在一起。
/// 这里的价值不是再做一层业务状态，而是确保 `SourceCoordinator`、提醒引擎
/// 和系统日历桥接控制器能够共享同一份偏好存储、时钟和生命周期。
///
/// ## 内部组合结构（T6 重构）
///
/// `AppRuntime` 内部使用 `CoreRuntime` + `ShellRuntime` 两个值类型容器实现逻辑分组：
/// - `core` 持有与业务状态机直接相关的对象（不依赖 AppKit 壳层）。
/// - `shell` 持有依赖 AppKit 壳层的控制器。
///
/// 为保持对外 API 向后兼容，`AppRuntime` 对其所有原有属性提供转发 `var`，
/// 消费方（视图层、`FeishuMeetingCountdownApp` 等）无需感知内部分组。
///
/// 详见 ADR `docs/adrs/2026-04-22-runtime-composition-and-event-bus.md`。
@MainActor
final class AppRuntime: ObservableObject {

    // MARK: Internal composition holders

    /// 业务状态机核心组件集合（不依赖 AppKit）。
    let core: CoreRuntime
    /// AppKit 壳层控制器集合。
    let shell: ShellRuntime

    // MARK: Forwarding properties (backward-compatible public API)

    /// 主数据源协调层。
    var sourceCoordinator: SourceCoordinator { core.sourceCoordinator }
    /// CalDAV / 系统日历配置控制器。
    var systemCalendarConnectionController: SystemCalendarConnectionController { core.systemCalendarConnectionController }
    /// 当前唯一的本地提醒引擎。
    var reminderEngine: ReminderEngine { core.reminderEngine }
    /// 设置页使用的提醒偏好控制器。
    var reminderPreferencesController: ReminderPreferencesController { core.reminderPreferencesController }
    /// 设置页使用的提醒音频库控制器。
    var soundProfileLibraryController: SoundProfileLibraryController { core.soundProfileLibraryController }
    /// 菜单栏秒级倒计时和闪烁共用的展示时钟。
    var menuBarPresentationClock: MenuBarPresentationClock { core.menuBarPresentationClock }
    /// 设置页使用的开机启动控制器。
    var launchAtLoginController: LaunchAtLoginController { shell.launchAtLoginController }
    /// 设置窗口控制器，负责记住 SwiftUI `Settings` scene 对应的真实 `NSWindow`。
    var settingsWindowController: SettingsWindowController { shell.settingsWindowController }
    /// AppKit 状态栏控制器负责真正把菜单栏按钮和浮层安装到系统菜单栏。
    var menuBarStatusItemController: MenuBarStatusItemController { shell.menuBarStatusItemController }
    /// 周期刷新与系统事件监听控制器。
    var appRefreshController: AppRefreshController { shell.appRefreshController }

    // MARK: Init

    init(core: CoreRuntime, shell: ShellRuntime) {
        self.core = core
        self.shell = shell
    }
}
