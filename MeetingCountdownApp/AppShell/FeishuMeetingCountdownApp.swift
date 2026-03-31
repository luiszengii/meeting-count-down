import SwiftUI

/// `FeishuMeetingCountdownApp` 是当前 macOS 菜单栏应用的总入口。
/// 它只负责声明场景和绑定全局状态对象，不在这里承载任何接入逻辑。
/// 入口把单一路径所需的协调层和系统日历配置控制器同时注入菜单栏与设置窗口，
/// 确保 UI 只消费聚合后的统一状态。
@main
struct FeishuMeetingCountdownApp: App {
    /// `AppRuntime` 把多个需要长期共存的状态对象绑在一起，避免 EventKit bridge 和偏好存储被重复创建。
    @StateObject private var appRuntime = AppContainer.makeAppRuntime()

    /// `body` 是 SwiftUI `App` 的场景声明入口。
    /// SwiftUI 会根据这里返回的场景树创建菜单栏入口和设置窗口。
    var body: some Scene {
        /// 菜单栏主入口始终只消费协调层暴露出来的聚合结果。
        MenuBarExtra(appRuntime.sourceCoordinator.menuBarTitle, systemImage: appRuntime.sourceCoordinator.menuBarSymbolName) {
            MenuBarContentView(
                sourceCoordinator: appRuntime.sourceCoordinator,
                settingsWindowController: appRuntime.settingsWindowController
            )
        }

        /// 设置窗口与菜单栏共享同一份协调层状态，避免两个窗口各自维护不同的数据源状态。
        Settings {
            SettingsView(
                sourceCoordinator: appRuntime.sourceCoordinator,
                systemCalendarConnectionController: appRuntime.systemCalendarConnectionController,
                settingsWindowController: appRuntime.settingsWindowController
            )
                .frame(minWidth: 420, idealWidth: 480, minHeight: 320)
                .padding(20)
        }
    }
}
