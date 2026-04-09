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
/// 入口把系统日历读取、提醒调度和设置窗口状态一起注入菜单栏与手动设置窗口，
/// 确保 UI 只消费聚合后的统一状态。
@main
struct FeishuMeetingCountdownApp: App {
    /// AppKit delegate 负责安装状态栏入口，同时强持有整套运行时依赖。
    @NSApplicationDelegateAdaptor(FeishuMeetingCountdownAppDelegate.self)
    private var appDelegate

    /// `body` 是 SwiftUI `App` 的场景声明入口。
    /// 菜单栏入口已经改由 AppKit delegate 安装；真正可缩放的设置窗口则由
    /// `SettingsWindowController` 手动创建。这里保留一个最小 `Settings` scene，
    /// 只是为了继续拥有系统级设置命令挂载点，不再依赖它提供真实窗口。
    var body: some Scene {
        let appRuntime = appDelegate.appRuntime

        Settings {
            EmptyView()
        }
        .commands {
            SettingsWindowCommands(
                reminderPreferencesController: appRuntime.reminderPreferencesController,
                openSettingsAction: {
                    appRuntime.settingsWindowController.requestWindowActivation()
                }
            )
        }
    }
}

/// app 菜单里的 `Settings…` / `Cmd+,` 同样要走手动设置窗口，
/// 否则会重新落回系统 `Settings` scene，导致窗口行为再次被锁死。
private struct SettingsWindowCommands: Commands {
    @ObservedObject var reminderPreferencesController: ReminderPreferencesController
    let openSettingsAction: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(commandTitle) {
                openSettingsAction()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    private var commandTitle: String {
        reminderPreferencesController.reminderPreferences.interfaceLanguage == .english
            ? "Settings…"
            : "设置…"
    }
}
