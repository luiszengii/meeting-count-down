# 2026-04-22 引入 AsyncStateController 协议统一 refresh/loading/error 模板

- 状态：Accepted
- 日期：2026-04-22
- 关联日志：暂无

## 背景

审计指出两个重复模式（M-2 / M-4），并在重构路线图 T2 中要求修复：

- **M-2**：`ReminderPreferencesController`、`SoundProfileLibraryController`、`SystemCalendarConnectionController` 三个 controller 各自用不同命名的字段实现同一套"刷新时切 loading flag、捕获错误写 errorMessage"模板，造成维护成本的三重叠加。
- **M-4**：各 controller 里的 `refresh()` 方法结构高度相似（`isXxx = true` → `defer { isXxx = false }` → `do/catch` → `lastXxxMessage = error.localizedDescription`），却因命名不统一而无法复用。

具体命名分歧如下：

| Controller | loading 标志 | error 字段 |
|---|---|---|
| `ReminderPreferencesController` | `isLoadingState` | `lastErrorMessage` |
| `SoundProfileLibraryController` | `isLoadingState` | `lastErrorMessage` |
| `SystemCalendarConnectionController` | `isLoadingState` | `lastErrorMessage` |

三者命名相同，但都不是最清晰的语义标识符，且无法通过协议共享实现。

## 决策

引入 `@MainActor protocol AsyncStateController`，要求：

1. 实现类暴露 `loadingState: Bool` 和 `errorMessage: String?` 两个统一命名属性。
2. 实现类提供 `performRefresh() async throws`，只包含真正的加载逻辑。
3. 协议通过默认扩展提供 `refresh()` 实现：开启 `loadingState`、清空 `errorMessage`、调用 `performRefresh()`、捕获异常写入 `errorMessage`、通过 `defer` 归位 `loadingState`。

三个 controller 全部迁移：

- `isLoadingState` → `loadingState`
- `lastErrorMessage` → `errorMessage`
- `refresh()` 主体 → `performRefresh()`

### 多 loading 标志的处理规则

`SoundProfileLibraryController` 有 `isImportingState` 和 `isApplyingState`，
`ReminderPreferencesController` 有 `isSavingState`，
`SystemCalendarConnectionController` 有 `isRequestingAccess`。

这些额外标志代表独立的写入或权限申请操作，语义上与"主读取刷新"区分明显，因此**保留为各自的独立 `@Published` 属性**，不合并进 `loadingState`。视图层需同时检查多个标志时，`Presentation.swift` 里的计算属性（如 `isSoundProfileEditingDisabled`）承担聚合职责。

### SystemCalendarConnectionController 的 refreshState() 入口

该 controller 对外历史上暴露 `refreshState()` 供视图层、内部通知回调调用。迁移后 `refreshState()` 保留为公开方法，内部直接委托给协议扩展的 `refresh()`，以维持向后兼容性并保证 `loadingState` 的统一管理。

### 关于 ReminderPreferencesController.performRefresh() 不会抛异常

`performRefresh()` 的实现调用 `preferencesStore.loadReminderPreferences()`，该接口签名为非抛出（load 失败回退默认值，不报错）。因此 `refresh()` 在这个 controller 上不会触发 `errorMessage` 写入路径。这是对存储层设计的有意保留，不影响协议的正确性；测试通过写入路径（`setGlobalReminderEnabled` 等）验证 `errorMessage` 的填充。

## 备选方案

### 方案 A：维持现状，各自实现

没有采用。原因是这会固化三处重复的样板代码，每次修改 loading/error 模式都需要同步修改三处，违背 DRY 原则；同时不同命名给新贡献者带来不必要的理解成本。

### 方案 B：用基类继承代替协议

没有采用。原因如下：
1. 三个 controller 的初始化参数差异显著，强行共享基类构造器会产生笨重的基类接口。
2. Swift 中 `@Published` 属性在子类继承场景下行为不稳定（`ObservableObject` 的 `objectWillChange` 合并需要特别处理）。
3. 协议扩展更能表达"只共享一段行为，不共享状态"的意图，也与 Swift 社区惯用风格更契合。

### 方案 C：只重命名，不提取协议

没有采用。统一命名解决了 M-2（命名不一致），但解决不了 M-4（重复样板）；引入协议才能彻底消除 `defer { loadingState = false }` 和 `catch { errorMessage = ... }` 的三重重复。

## 影响

- 三个 controller 对外暴露的属性名称改变（`isLoadingState` → `loadingState`，`lastErrorMessage` → `errorMessage`）；所有消费这些属性的视图文件和测试文件已同步更新。
- 任何未来新增的、具有"主读取刷新 + loading + error"模式的 controller，只需遵从 `AsyncStateController` 并实现 `performRefresh()` 即可，无需重写样板。
- `LaunchAtLoginController` 同样有 `isApplyingState` 和 `lastErrorMessage`，但其操作语义（设置开机登录）与"主读取刷新"模式不同，本次未迁移。如未来觉得有必要也可独立评估。

## 后续动作

1. 如果 `LaunchAtLoginController` 后续也需要统一，可再评估是否迁移或为"写入类操作"单独定义一个 `AsyncWriteController` 协议变体。
2. 如果有新 controller 引入类似模式，应直接遵从 `AsyncStateController` 而不是重新发明。
