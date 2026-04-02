import AppKit
import SwiftUI

/// `FeishuMeetingCountdownAppDelegate` 用 AppKit 生命周期把真正的状态栏入口安装到系统菜单栏。
/// SwiftUI `App` 仍然负责设置窗口场景，但菜单栏按钮本身改回 `NSStatusItem`，
/// 这样最后 `10` 秒的红色胶囊背景就不会再受 `MenuBarExtra` 宿主限制。
@MainActor
final class FeishuMeetingCountdownAppDelegate: NSObject, NSApplicationDelegate {
    /// 运行时依赖只创建一次，供菜单栏入口和设置窗口共同复用。
    let appRuntime = AppContainer.makeAppRuntime()

    func applicationDidFinishLaunching(_ notification: Notification) {
        appRuntime.menuBarStatusItemController.installIfNeeded()
    }
}

/// `FeishuMeetingCountdownApp` 是当前 macOS 菜单栏应用的总入口。
/// 它只负责声明场景和绑定全局状态对象，不在这里承载任何接入逻辑。
/// 入口把系统日历读取、提醒调度和设置窗口状态一起注入菜单栏与设置页，
/// 确保 UI 只消费聚合后的统一状态。
@main
struct FeishuMeetingCountdownApp: App {
    /// AppKit delegate 负责安装状态栏入口，同时强持有整套运行时依赖。
    @NSApplicationDelegateAdaptor(FeishuMeetingCountdownAppDelegate.self)
    private var appDelegate

    /// `body` 是 SwiftUI `App` 的场景声明入口。
    /// 菜单栏入口已经改由 AppKit delegate 安装；SwiftUI 这里只保留设置窗口场景。
    var body: some Scene {
        let appRuntime = appDelegate.appRuntime

        /// 设置窗口与菜单栏共享同一份协调层和提醒层状态，避免两个窗口各自维护不同的运行态。
        Settings {
            SettingsView(
                sourceCoordinator: appRuntime.sourceCoordinator,
                systemCalendarConnectionController: appRuntime.systemCalendarConnectionController,
                reminderEngine: appRuntime.reminderEngine,
                reminderPreferencesController: appRuntime.reminderPreferencesController,
                soundProfileLibraryController: appRuntime.soundProfileLibraryController,
                launchAtLoginController: appRuntime.launchAtLoginController,
                settingsWindowController: appRuntime.settingsWindowController
            )
                .frame(minWidth: 420, idealWidth: 480, minHeight: 320)
                .padding(20)
        }
    }
}
