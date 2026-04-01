import SwiftUI

/// `FeishuMeetingCountdownApp` 是当前 macOS 菜单栏应用的总入口。
/// 它只负责声明场景和绑定全局状态对象，不在这里承载任何接入逻辑。
/// 入口把系统日历读取、提醒调度和设置窗口状态一起注入菜单栏与设置页，
/// 确保 UI 只消费聚合后的统一状态。
@main
struct FeishuMeetingCountdownApp: App {
    /// `AppRuntime` 把多个需要长期共存的状态对象绑在一起，避免桥接层和提醒层被重复创建。
    @StateObject private var appRuntime = AppContainer.makeAppRuntime()

    /// `body` 是 SwiftUI `App` 的场景声明入口。
    /// SwiftUI 会根据这里返回的场景树创建菜单栏入口和设置窗口。
    var body: some Scene {
        /// 菜单栏主入口直接消费协调层和提醒层的聚合结果。
        /// 标签本身单独交给 `MenuBarLabelView` 观察运行态，
        /// 这样倒计时变化和提醒命中时的菜单栏可见提示都能实时刷新。
        MenuBarExtra {
            MenuBarContentView(
                sourceCoordinator: appRuntime.sourceCoordinator,
                reminderEngine: appRuntime.reminderEngine,
                settingsWindowController: appRuntime.settingsWindowController
            )
        } label: {
            MenuBarLabelView(
                sourceCoordinator: appRuntime.sourceCoordinator,
                reminderEngine: appRuntime.reminderEngine
            )
        }

        /// 设置窗口与菜单栏共享同一份协调层和提醒层状态，避免两个窗口各自维护不同的运行态。
        Settings {
            SettingsView(
                sourceCoordinator: appRuntime.sourceCoordinator,
                systemCalendarConnectionController: appRuntime.systemCalendarConnectionController,
                reminderEngine: appRuntime.reminderEngine,
                settingsWindowController: appRuntime.settingsWindowController
            )
                .frame(minWidth: 420, idealWidth: 480, minHeight: 320)
                .padding(20)
        }
    }
}
