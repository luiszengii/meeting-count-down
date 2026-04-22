import Foundation

/// 统一三个 controller 的 refresh + loading + error 模板。
/// 实现类只需要把真正的"加载逻辑"塞进 `performRefresh()`，
/// 协议默认 `refresh()` 负责 `loadingState` flag 切换 + 异常 → `errorMessage`。
///
/// 适用场景：controller 有一个主要的"读取并刷新状态"操作，
/// 且对外暴露 `loadingState`（忙碌标志）和 `errorMessage`（最近一次可见错误）。
///
/// 如果 controller 还有独立的"写入"忙碌状态（如 `isSavingState`、`isImportingState`、
/// `isApplyingState`），这些额外状态可以保留为各自的 `@Published` 属性，
/// 与本协议定义的 `loadingState` 并列存在，互不干扰。
/// 详见 ADR `docs/adrs/2026-04-22-async-state-controller.md`。
@MainActor
protocol AsyncStateController: AnyObject, ObservableObject {
    /// 当前是否正在执行主读取操作（对应原各 controller 的 `isLoadingState`）。
    var loadingState: Bool { get set }
    /// 最近一次需要展示给用户的错误（对应原各 controller 的 `lastErrorMessage`）。
    var errorMessage: String? { get set }
    /// 子类实现真正的加载逻辑；`refresh()` 负责包裹 loading flag 和错误捕获。
    func performRefresh() async throws
}

extension AsyncStateController {
    /// 执行一次完整刷新：先置 `loadingState = true`，清空 `errorMessage`，
    /// 调用 `performRefresh()`，最后通过 `defer` 保证 `loadingState` 归位。
    /// 若 `performRefresh()` 抛出，则把错误描述写入 `errorMessage`。
    func refresh() async {
        loadingState = true
        errorMessage = nil
        defer { loadingState = false }
        do {
            try await performRefresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
