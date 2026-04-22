import Combine
import Foundation

/// `RefreshEventBus` 是一个轻量事件总线，用于把"需要触发刷新"的信号从各设置控制器
/// 传递给 `SourceCoordinator`，而不需要每个控制器都持有协调层的弱引用。
///
/// ## 设计动机
///
/// 原来三个控制器（`SystemCalendarConnectionController`、`ReminderPreferencesController`、
/// `SoundProfileLibraryController`）各自在 `init` 里接受一个 `onXxxChanged: () async -> Void`
/// 闭包，并在对应事件发生时调用它。这种模式在只有一两个触发源时尚可，但随着触发源增加
/// 会导致闭包数量爆炸、`AppContainer` 装配逻辑变得冗长、且每个控制器都要感知
/// `SourceCoordinator` 的弱引用捕获细节。
///
/// `RefreshEventBus` 把"发送刷新信号"与"消费刷新信号"彻底解耦：
/// - 控制器只需调用 `bus.send(.someRefreshTrigger)` 即可，不再感知下游。
/// - `SourceCoordinator` 在 `AppContainer` 装配时订阅总线，接收到事件后调用 `refresh(trigger:)`。
/// - 总线本身是无状态的，既不缓存历史事件也不持有任何业务对象，随时可以测试。
///
/// ## 生命周期
///
/// `AppContainer.makeAppRuntime()` 创建一个单例 `RefreshEventBus` 实例，
/// 把它同时传给所有生产者控制器和消费者（`SourceCoordinator`）。
/// Bus 实例本身由 `AppRuntime` 间接持有（通过各控制器和协调层的 `cancellables`）。
final class RefreshEventBus {
    /// 内部 Combine 主题；无 failure 保证总线不会因单条事件失败而终止订阅。
    private let subject = PassthroughSubject<RefreshTrigger, Never>()

    /// 对外暴露只读的 `Publisher`，供消费者订阅。
    /// 使用 `AnyPublisher` 隐藏内部实现，避免外部直接向主题发送事件。
    var publisher: AnyPublisher<RefreshTrigger, Never> {
        subject.eraseToAnyPublisher()
    }

    /// 向总线发布一个刷新触发事件。
    /// 调用方无需关心谁订阅了这个总线；该方法仅在 `@MainActor` 上下文中被调用，
    /// 因为三个生产者控制器都是 `@MainActor` 隔离的。
    func send(_ trigger: RefreshTrigger) {
        subject.send(trigger)
    }
}
