import SwiftUI

/// `FeishuMeetingCountdownApp` 是当前 macOS 菜单栏应用的总入口。
/// 它只负责声明场景和绑定全局状态对象，不在这里承载任何接入逻辑。
/// Phase 0 的目标是先把应用壳层跑起来，因此入口只装配一个 `SourceCoordinator`
/// 并把它同时注入菜单栏内容和设置窗口，确保 UI 只消费聚合后的统一状态。
@main
struct FeishuMeetingCountdownApp: App {
    /// `@StateObject` 负责让协调层在整个 App 生命周期内只初始化一次。
    /// 这里不能写成普通属性，否则 SwiftUI 在视图重建时可能重复创建状态对象。
    @StateObject private var sourceCoordinator = AppContainer.makeSourceCoordinator()

    /// `body` 是 SwiftUI `App` 的场景声明入口。
    /// SwiftUI 会根据这里返回的场景树创建菜单栏入口和设置窗口。
    var body: some Scene {
        /// 菜单栏主入口始终只消费协调层暴露出来的聚合结果。
        MenuBarExtra(sourceCoordinator.menuBarTitle, systemImage: sourceCoordinator.menuBarSymbolName) {
            MenuBarContentView(sourceCoordinator: sourceCoordinator)
        }

        /// 设置窗口与菜单栏共享同一份协调层状态，避免两个窗口各自维护不同的数据源状态。
        Settings {
            SettingsView(sourceCoordinator: sourceCoordinator)
                .frame(minWidth: 420, idealWidth: 480, minHeight: 320)
                .padding(20)
        }
    }
}
