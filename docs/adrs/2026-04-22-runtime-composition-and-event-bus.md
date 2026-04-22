# 2026-04-22 AppRuntime 内部分组与 RefreshEventBus 事件总线

- 状态：Accepted
- 日期：2026-04-22
- 关联日志：暂无

## 背景

审计条目 A-1 / A-2 / M-9 和重构路线图任务 T6 指出两个相互独立但协同改进的问题：

**A-1 / A-2：AppRuntime 是 10 属性 God Object。**
`AppRuntime` 同时持有"业务状态机"（`SourceCoordinator`、`ReminderEngine`、
`ReminderPreferencesController`、`SoundProfileLibraryController`、
`SystemCalendarConnectionController`、`MenuBarPresentationClock`）和
"AppKit 壳层控制器"（`LaunchAtLoginController`、`SettingsWindowController`、
`MenuBarStatusItemController`、`AppRefreshController`），两种职责混在同一层级，
不体现任何分层意图，影响可读性和后续扩展。

**M-9：分散的闭包回调链。**
三个控制器（`SystemCalendarConnectionController`、`ReminderPreferencesController`、
`SoundProfileLibraryController`）各自在 `init` 里接受 `onXxxChanged: () async -> Void`
闭包，在对应事件发生时调用它来触发 `SourceCoordinator.refresh(trigger:)`。
这种模式在触发源较少时尚可，但随着多数据源（T8）的引入，闭包数量会线性增长，
且每个控制器都要感知并弱引用 `SourceCoordinator`，耦合度高、装配噪声大。

**保守范围原则。**
T6 明确要求"保守范围——不做破坏每个消费方的完全拆分"。视图层和
`FeishuMeetingCountdownApp` 已经广泛引用 `appRuntime.xxx` 属性，
在当前阶段全量改为 `appRuntime.core.xxx` / `appRuntime.shell.xxx` 收益不抵风险，
应遵守增量演进原则。

## 决策

### 1. AppRuntime 内部分组（组合而非替换）

引入 `CoreRuntime` 和 `ShellRuntime` 两个值类型（`struct`），作为 `AppRuntime`
的内部容器，实现逻辑分组而不破坏对外 API：

**CoreRuntime**（业务状态机，不依赖 AppKit）：
- `sourceCoordinator`
- `systemCalendarConnectionController`
- `reminderEngine`
- `reminderPreferencesController`
- `soundProfileLibraryController`
- `menuBarPresentationClock`

**ShellRuntime**（AppKit 壳层控制器）：
- `launchAtLoginController`
- `settingsWindowController`
- `menuBarStatusItemController`
- `appRefreshController`

`AppRuntime` 持有 `let core: CoreRuntime` 和 `let shell: ShellRuntime`，
同时对所有原有属性提供转发 `var`（如 `var reminderEngine: ReminderEngine { core.reminderEngine }`），
保证所有消费方零改动。

### 2. 引入 RefreshEventBus 替换闭包回调链

新建 `MeetingCountdownApp/Shared/RefreshEventBus.swift`，用一个类包装
`PassthroughSubject<RefreshTrigger, Never>`：

- **生产者**：三个控制器不再接受 `onXxxChanged` 闭包，改为接受注入的
  `RefreshEventBus?`（可选，确保测试场景向后兼容）。
  事件发生时调用 `bus.send(trigger)` 即可，不感知下游消费者。
- **消费者**：`SourceCoordinator` 的 `init` 增加可选 `refreshEventBus` 参数；
  如果注入了总线，则订阅 `bus.publisher`，在主 RunLoop 上接收事件并调用
  `refresh(trigger:)`。`AnyCancellable` 存入私有属性保证订阅与协调层生命周期一致。
- **装配点**：`AppContainer.makeAppRuntime()` 创建唯一的 `RefreshEventBus` 实例，
  同时传给四个对象（三个生产者 + 一个消费者），一次装配完毕。

事件流向：

```
SystemCalendarConnectionController ─┐
ReminderPreferencesController      ─┤─ RefreshEventBus ──► SourceCoordinator.refresh(trigger:)
SoundProfileLibraryController      ─┘
```

`RefreshTrigger` 枚举已有所有需要的 case（`manualRefresh`、`systemCalendarChanged`、
`preferencesChanged`），无需添加新 case。

## 备选方案

### 方案 A：完全拆 AppRuntime，让消费方分别持有 CoreRuntime + ShellRuntime

没有采用。当前视图层引用面广（`SettingsView`、`MenuBarStatusItemController`、
`FeishuMeetingCountdownApp` 等多处直接访问 `appRuntime.xxx`），全量改动涉及的
diff 面积远超 T6 的保守范围定义，且带来的架构收益在视图层尚未重构之前并不明显。
遵守增量演进原则：先做内部分组，等 T8 多数据源接入时再评估是否值得暴露 `CoreRuntime`
给消费方直接持有。

### 方案 B：保持现状，继续使用闭包链

没有采用。当前闭包链在单数据源场景下勉强可以接受，但 T8 计划引入多个数据源和
多个触发场景，届时每加一个触发源就需要新增一个闭包参数并修改 `AppContainer`
装配逻辑。这种模式的闭包数量会线性爆炸，而且每个控制器都要感知
`SourceCoordinator` 的弱引用捕获细节，耦合度高，可测性差。

## 影响

- `AppRuntime` 的对外属性（公共 API）完全不变；消费方零改动。
- 三个控制器的 `init` 签名变化：`onXxxChanged` 闭包参数替换为 `refreshEventBus: RefreshEventBus?`。
  旧闭包默认值（`= {}`）替换为 `= nil`，测试场景可以不传，不影响已有测试逻辑。
- `SourceCoordinator` 增加可选 `refreshEventBus` 参数（尾参数，有默认值 `nil`），
  现有调用点不受影响。
- 需要在 `SourceCoordinator` 中 `import Combine`，在相关测试文件中也 `import Combine`。
- `AppContainer.makeAppRuntime()` 增加 `RefreshEventBus` 单例的创建和传递逻辑。

## 后续动作

1. T8（多数据源）接入时，再评估是否把 `CoreRuntime` 作为独立类型暴露给消费方直接持有，
   届时可以把现有转发属性整体替换，不需要重新设计分层结构。
2. 如果将来需要从其他触发源（如 CloudKit 同步完成、Siri 意图等）发送刷新信号，
   直接向 `RefreshEventBus` 注入新生产者即可，无需修改 `SourceCoordinator` 或
   `AppContainer` 的核心逻辑。
