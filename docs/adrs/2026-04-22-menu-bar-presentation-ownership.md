# 2026-04-22 明确菜单栏 Presentation 真值方为 ReminderState，MenuBarStatusItemController 收缩为 AppKit 宿主

- 状态：Accepted
- 日期：2026-04-22
- 关联日志：暂无

## 背景

审计问题 M-7（职责混杂）和 A-3（双源真值）指出，`MenuBarStatusItemController`（474 行）同时承担了五个无关职责：

1. `NSStatusItem` 宿主（AppKit 控件生命周期）
2. `NSPopover` 控制器（弹层展示与关闭）
3. `ReminderState` → `StatusItemPresentation` 翻译（领域状态到展示值）
4. 倒计时文案格式化（`localizedCountdownLine`、`localizedMenuBarTitle` 等）
5. 红色闪烁逻辑（`shouldHighlightCountdownRed`）

其中第 3–5 项已在 `ReminderState.menuBarAlertPresentation(at:)` 中有等价实现，导致同一业务规则存在两份分散的代码。`localizedAlertPresentation(at:)` 与 `ReminderState.playingPresentation(for:at:)` 的逻辑实质相同，只加了界面语言分支。两份实现必须同步维护，审计标记为 A-3（双源真值）。

本决策对应重构路线图（refactor-roadmap-2026-04-22.md）任务 T4。

## 决策

把 `ReminderMenuBarAlertPresentation` 的真值归属明确给 `ReminderState`。`MenuBarStatusItemController` 收缩为纯粹的 AppKit 宿主层，通过两个新文件实现职责分离：

### `MenuBarPresentationCalculator`（纯值计算器）

- 无状态 `enum`，公开一个纯函数 `calculate(reminderState:sourceCoordinatorState:now:uiLanguage:) -> MenuBarPresentation`。
- 调用 `ReminderState.menuBarAlertPresentation(at:)` 获取提醒命中 presentation，再叠加界面语言本地化——不重新推导任何闪烁或倒计时规则。
- 普通态（倒计时文案、健康标签）的格式化逻辑从 controller 迁移至此，集中管理。
- 不依赖 AppKit，不持有可变状态，可在任意 actor 调用。

### `MenuBarAppKitHost`（AppKit 宿主）

- `@MainActor final class`，持有 `NSStatusItem`、`NSPopover`，负责控件生命周期。
- 对外暴露 `installIfNeeded()`、`apply(presentation:)`、`togglePopover()`、`dismissPopover()`。
- 所有 NSColor / NSFont / 胶囊背景 / 宽度数学集中于此，不再散落 controller。
- 弹层内容和按钮动作由调用方通过闭包注入，宿主本身无业务依赖。

### `MenuBarStatusItemController`（编排层，收缩）

- 持有 calculator、host 和 Combine 订阅。
- 唯一职责：把 `Publishers.CombineLatest3(sourceCoordinator.$state, reminderEngine.$state, menuBarPresentationClock.$now)` 管线接到 `calculator.calculate → host.apply` 的数据流上。
- 不再包含任何 presentation 计算逻辑，不直接操作 NSStatusItem / NSPopover。

## 备选方案

### 方案 A：由 MenuBarStatusItemController 持续承担计算

没有采用。原因：`localizedAlertPresentation(at:)` 和 `ReminderState.menuBarAlertPresentation(at:)` 已是双源真值；每次提醒规则变更（闪烁阈值、新 SilentTriggerReason 等）都必须同步修改两处。这直接违反 A-3 修复目标，且阻塞了后续 calculator 的 snapshot 测试（T10）。

### 方案 B：把 presentation 计算再下沉到 ReminderEngine 而不是 ReminderState

没有采用。原因：`ReminderState` 是纯值数据模型（`enum`，`Equatable`，`Sendable`），已经承载了 `menuBarAlertPresentation(at:)` 的实现。`ReminderEngine` 是状态机（持有 Task、调度器、音频引擎），职责是驱动状态转换，不应反向依赖展示逻辑。把 presentation 方法放在 state 枚举里，能保持 state 的自包含性，也方便对单个 case 做单元测试。分离 state 与 engine 是 Phase 4 的核心设计，不应在此混合。

## 影响

- `MenuBarStatusItemController` 从 474 行减少至约 130 行（降幅 ≥ 40%）。
- `MenuBarPresentationCalculator` 是纯函数，无 AppKit 依赖，可在 macOS 单元测试目标中直接覆盖，无需 UI 宿主环境。
- `MenuBarAppKitHost` 的测试可通过 UI 快照测试（T10）补充，当前阶段不是阻塞项。
- `ReminderState.menuBarAlertPresentation(at:)` 保持不变，现有 `ReminderStateTests` 继续有效。
- `MenuBarStatusItemController` 内 `localizedAlertPresentation(at:)`、`localizedMenuBarTitle(at:)`、`localizedCountdownLine(until:now:)`、`shouldHighlightCountdownRed(at:remainingSeconds:)` 及 `StatusItemPresentation` 结构体全部删除。
- 新增文件均通过 xcodegen path glob 自动纳入构建，无需修改 `project.yml`。

## 后续动作

1. T10 将为 `MenuBarPresentationCalculator` 补充 snapshot 测试，覆盖更复杂的组合输入场景。
2. 如果后续引入第三种界面语言，只需修改 `MenuBarPresentationCalculator` 的 `localized(_:_:uiLanguage:)` 辅助方法，无需触及 `ReminderState` 或 `MenuBarAppKitHost`。
