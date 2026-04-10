# AGENTS.md

## 模块名称

`Settings`

## 模块目的

负责菜单栏应用设置窗口的拆分后 UI 结构。这里承载设置页各 tab 的视图骨架、共享展示组件和展示态文案辅助，不负责 EventKit 读取、提醒调度或偏好持久化本身。

## 包含内容

- `Header.swift`：设置窗口头部、tab 导航和页面切换入口。
- `OverviewPage.swift`：概览页布局与下一场会议展示。
- `CalendarPage.swift`：CalDAV 接入步骤与系统日历选择页。
- `RemindersPage.swift`：提醒播放策略与会议过滤页。
- `AudioPage.swift`：提醒音频、倒计时和声音列表页。
- `AdvancedPage.swift`：语言、同步、诊断等低频维护项。
- `Components.swift`：跨页共享行组件、卡片和提示块。
- `Presentation.swift`：设置页展示态推导、文案组装、tab 枚举和过渡动画。

## 关键依赖

- SwiftUI
- AppKit
- `GlassUI`
- `SourceCoordinator`
- `ReminderEngine`
- `ReminderPreferencesController`
- `SoundProfileLibraryController`
- `SystemCalendarConnectionController`
- `LaunchAtLoginController`

## 关键状态 / 数据流

设置页子文件仍通过 `SettingsView` 统一持有的控制器读取聚合状态，并把显式动作交回对应 controller 或协调层。这个目录只做壳层展示和用户操作路由，不重新推导“下一场会议”或提醒调度规则。需要跨 tab 复用的展示态计算统一放在 `Presentation.swift`，避免同一段文案和状态解释在多个页面里重复漂移。

## 阅读入口

先看 `../SettingsView.swift` 理解壳层入口和状态所有权，再看 `Header.swift`、`OverviewPage.swift` 和 `CalendarPage.swift`，最后再看 `Components.swift` 与 `Presentation.swift`。

## 开发注意事项

- 这里只能消费现成状态并发出动作，不要把业务规则重新写进页面文件。
- 跨页复用的组件和展示态推导必须抽到共享文件，不要为了方便把重复代码复制回 tab 文件。
- 新增 SwiftUI 文件继续遵守学习导向的中文注释要求：核心类型、关键方法和复杂状态切换默认要写函数级或模块级注释，整体注释密度目标约为每 `8` 到 `10` 行有效代码至少有 `1` 行高信息量注释。
- 视觉结构拆分后，优先通过显式参数和 `SettingsView` 共享状态协作，不要在子文件里偷偷创建新的状态源或定时器。
