import Foundation

/// `StartupError` 描述应用在装配运行期依赖（`AppContainer.makeAppRuntime()`）阶段
/// 可能出现的失败原因。
///
/// 当前所有子组件构造器都是不可抛出的，所以这个枚举暂时没有真实的抛出方。
/// 之所以提前定义出来，是为了在未来某个组件需要做异步预检（例如音频引擎的
/// `warmUp`、偏好存储迁移、EventKit 同步授权检查）改成 throws 时，能直接走
/// 同一种错误通道，而不必再大改 `FeishuMeetingCountdownApp` 的 scene 与回退 UI。
///
/// 触发约定：
/// - 真正失败的子组件应当把底层错误包装成最贴近自身领域的 case；
/// - 没有匹配领域的失败统一用 `.unexpected(stage:underlying:)`，`stage` 用一个
///   人类可读的英文短串（例如 `"audio"`、`"preferences"`、`"calendar"`），
///   方便日志聚合时归类。
enum StartupError: Error {
    /// 音频引擎或音频路由初始化失败。
    case audioEngineUnavailable(underlying: Error)
    /// 用户偏好存储装载失败（例如未来的迁移逻辑抛错）。
    case preferencesStoreUnavailable(underlying: Error)
    /// 其他未明确归类的启动失败，`stage` 标记发生位置。
    case unexpected(stage: String, underlying: Error)
}

extension StartupError: LocalizedError {
    /// 给用户看的中文描述。回退 UI 直接用这个串拼接提示，不再二次本地化。
    var errorDescription: String? {
        switch self {
        case .audioEngineUnavailable(let underlying):
            return "提醒音频组件初始化失败：\(underlying.localizedDescription)"
        case .preferencesStoreUnavailable(let underlying):
            return "用户偏好存储初始化失败：\(underlying.localizedDescription)"
        case .unexpected(let stage, let underlying):
            return "启动阶段「\(stage)」初始化失败：\(underlying.localizedDescription)"
        }
    }
}
