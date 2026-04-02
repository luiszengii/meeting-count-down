import SwiftUI

/// `SettingsSceneOpenController` 把 SwiftUI 官方提供的 `openSettings` 动作桥接给壳层控制器。
/// `NSStatusItem` / `NSPopover` 这条 AppKit 菜单栏链路本身拿不到 SwiftUI 场景环境值，
/// 因此需要由弹层里的 SwiftUI 视图在渲染时登记一次，再交给状态栏控制器复用。
@MainActor
final class SettingsSceneOpenController {
    /// 真正创建或唤起 SwiftUI `Settings` scene 的官方动作。
    /// 这里不直接存 `OpenSettingsAction`，而是存成普通闭包，避免壳层继续感知 SwiftUI 环境类型。
    private var openSettingsAction: (() -> Void)?

    /// 菜单弹层解析到官方设置动作后，把最新动作登记进来。
    /// 之所以允许重复覆盖，是因为 `NSPopover` 内容可能在不同显示周期里被重新挂载。
    func register(action: @escaping () -> Void) {
        openSettingsAction = action
    }

    /// 当状态栏控制器需要打开设置时，统一走这里。
    /// 如果动作还没登记成功，就返回 `false`，交给上层决定是否记录日志或忽略。
    @discardableResult
    func openSettingsIfAvailable() -> Bool {
        guard let openSettingsAction else {
            return false
        }

        openSettingsAction()
        return true
    }
}
