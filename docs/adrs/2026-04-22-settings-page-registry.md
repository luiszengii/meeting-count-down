# 2026-04-22 将设置页从 SettingsView 扩展转为独立 SettingsPage 结构体注册表

- 状态：Accepted
- 日期：2026-04-22
- 关联日志：暂无

## 背景

审计问题 E-4（扩展滥用）和 M-11（SettingsView 状态泛滥）指出，`SettingsView` 通过大量 `extension SettingsView` 块承载了五个设置 Tab 的全部 UI、状态、展示逻辑和本地化文本。这带来两个核心问题：

1. **页面状态混杂在壳层**：`hoveredSoundProfileID`、`calendarSearchQuery`、`isCalendarConfigurationExpanded`、`didCopyCalendarDiagnostics` 等完全属于单个页面的局部状态，却在 `SettingsView` 上声明，任何页面的状态需求变化都会改动主 `struct`。
2. **无法独立推理每个页面**：五个 Tab 的 UI 代码全部隐式共享 `SettingsView` 的 `self` 作用域，使得阅读或测试任何一个页面时都需要在散布于多个文件的扩展中反复跳转。

本决策对应重构路线图（refactor-roadmap-2026-04-22.md）任务 T5。

## 决策

引入 `SettingsPage` 协议，将五个设置页从 `extension SettingsView` 转换为独立的具名 `struct` 类型，并通过 `SettingsView` 上的 `pages: [any SettingsPage]` 注册表统一路由：

```swift
protocol SettingsPage {
    var id: SettingsTab { get }
    var titleKey: (chinese: String, english: String) { get }
    @MainActor func body(uiLanguage: AppUILanguage) -> AnyView
}
```

五个页面结构体：`OverviewPage`、`CalendarPage`、`RemindersPage`、`AudioPage`、`AdvancedPage`。

每个页面结构体持有自身所需的控制器引用（`@ObservedObject`），并通过私有的内部 `struct XxxPageBody: View` 持有页面局部 `@State`（`hoveredSoundProfileID`、`calendarSearchQuery`、`isCalendarConfigurationExpanded`、`didCopyCalendarDiagnostics`）。

同时在 `SettingsLocalizationPresentation.swift` 新增模块级自由函数：

```swift
func localized(_ chinese: String, _ english: String, in language: AppUILanguage) -> String
```

供各页面 body struct 调用，不依赖 `SettingsView` 实例。

## 备选方案

### 方案 A：保留 extension SettingsView，仅拆分文件

没有采用。页面局部状态仍然声明在 `SettingsView` 上，每增加一个新 Tab 就需要修改主 `struct`，不解决 M-11 的根本问题。

### 方案 B：使用 associatedtype Body: View 的泛型协议

没有采用。Swift 协议存在型（`any SettingsPage`）不支持关联类型，`[any SettingsPage]` 数组无法用泛型协议表达，需要额外的类型消除包装器。

### 方案 C（已选）：返回 AnyView 的协议方法

`body(uiLanguage:) -> AnyView` 允许直接使用 `[any SettingsPage]` 数组，无类型消除样板，代价是在协议边界处发生一次类型擦除。对于设置页这种低频渲染场景，性能损耗可以接受。

## 影响

- **SettingsView 精简**：去除 5 项页面局部 `@State`，去除 `onAppear`/`onChange` 日历展开逻辑，主 `struct` 降至约 65 行。
- **Header.swift tabContent** 从硬编码 5 段 `if selectedTab ==` 改为注册表迭代，新增 Tab 只需添加一个页面 struct。
- **跨页面导航**：`OverviewPage` 通过 `onNavigate: (SettingsTab) -> Void` 回调修改壳层 `selectedTab`，避免页面直接持有壳层引用。
- **fileImporter 绑定**：`.fileImporter` 修饰器留在 `SettingsView`，`AudioPage` 通过 `@Binding<Bool>` 接收 `isPresentingSoundImporter`。
- **测试**：`SettingsPresentationTests` 直接构造 `SettingsView` 并测试其扩展方法（`overviewHeaderBadges`、`localizedCalendarConnectionDiagnosticSummary`），这些方法未被迁移，测试无需改动。
- **构建**：新文件通过 xcodegen path glob 自动纳入，无需修改 `project.yml`。

## 后续动作

1. P2 T7（i18n 整体迁移）将替换各页面 body struct 中的 `localized(_:_:in:)` 调用，统一接入字符串目录或 `.strings` 资源。
2. 如有新 Tab 需求，实现 `SettingsPage` 协议后加入 `SettingsView.pages` 数组即可，不改动任何现有页面或壳层代码。
3. `Components.swift` 中的共享 UI 辅助方法（`pageIntro`、`preferenceToggleRow` 等）仍为 `extension SettingsView`；如未来需要在页面 body struct 外部复用，可提取为自由函数或独立视图。
