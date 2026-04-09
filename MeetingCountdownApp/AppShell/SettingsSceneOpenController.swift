/// `SettingsSceneOpenController` 统一桥接“打开设置窗口”的显式动作。
/// 这轮不再依赖 SwiftUI 官方 `openSettings` 环境值，而是让壳层装配阶段直接登记
/// 一条手动前置设置窗口的闭包；菜单栏、app 菜单和未来其他入口都复用同一条链路。
@MainActor
final class SettingsSceneOpenController {
    /// 真正创建或唤起设置窗口的动作。
    private var openSettingsAction: (() -> Void)?

    /// 壳层装配阶段把当前最新的打开设置动作登记进来。
    /// 这里仍然允许覆盖，方便未来如果窗口实现再次切换时保留同一份调用协议。
    func register(action: @escaping () -> Void) {
        openSettingsAction = action
    }

    /// 当菜单栏或 app 菜单需要打开设置时，统一走这里。
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
