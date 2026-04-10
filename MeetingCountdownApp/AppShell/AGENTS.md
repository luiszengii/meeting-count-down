# AGENTS.md

## 模块名称

`AppShell`

## 模块目的

负责应用运行壳层：SwiftUI `App` 入口、菜单栏内容、设置窗口和依赖装配。它只消费聚合后的应用状态，不直接承担 EventKit 原始读取或系统日历配置细节。

## 包含内容

- `FeishuMeetingCountdownApp.swift`：应用入口和场景定义。
- `MenuBarStatusItemController.swift`：用 `NSStatusItem + NSPopover` 托管真正的菜单栏按钮和弹出内容。
- `SettingsSceneOpenController.swift`：把“打开设置窗口”的显式动作桥接给菜单栏入口和 app 菜单。
- `AppContainer.swift`：组装 CalDAV 主链路所需依赖。
- `AppRuntime.swift`：持有应用级长生命周期对象，避免控制器在 SwiftUI 场景切换时被释放。
- `MenuBarContentView.swift`：菜单栏弹出内容。
- `GlassUI.swift`：菜单栏弹层和设置页共享的毛玻璃材质、卡片、胶囊按钮与导航组件。
- `MenuBarPresentationClock.swift`：为菜单栏标签提供秒级倒计时和闪烁所需的受控时钟。
- `SettingsView.swift`：设置窗口壳层入口；现在主要负责注入依赖、tab 切换和文件导入。
- `Settings/`：设置窗口拆分后的子目录；按 `Overview / Calendar / Reminders / Audio / Advanced` 和共享组件拆开 `SettingsView` 的 extension 文件。
- `LaunchAtLoginController.swift`：把 `ServiceManagement` 登录项状态包装成设置页可消费的状态对象。
- `AppRefreshController.swift`：统一管理 `120s / 30s` 周期刷新、睡眠唤醒与时区变化后的重读。

## 关键依赖

- SwiftUI
- AppKit
- ServiceManagement
- `SourceCoordinator`
- `ReminderEngine`
- `ReminderPreferencesController`
- `SoundProfileLibraryController`
- `SystemCalendarConnectionController`

## 关键状态 / 数据流

`AppShell` 从 `SourceCoordinator`、`ReminderEngine`、`ReminderPreferencesController`、`SoundProfileLibraryController`、`LaunchAtLoginController` 和 `SystemCalendarConnectionController` 读取聚合状态，再把显式动作交回这些控制器或协调层。菜单栏秒级倒计时与最后 `10` 秒闪烁由 `MenuBarPresentationClock` 提供渲染时钟，但真正负责把菜单栏按钮安装到系统菜单栏的是 `MenuBarStatusItemController`；它只消费现成的 presentation，不重新推导提醒规则。设置页现在由 `SettingsWindowController` 手动创建和持有 `NSWindow`，这样窗口尺寸和前置行为都能被壳层稳定控制；菜单栏弹层和 app 菜单如果需要打开设置页，都统一通过 `SettingsSceneOpenController` 复用同一条显式打开动作。真正的会议重读仍只能通过 `SourceCoordinator.refresh(trigger:)` 进入主链路，避免 View 自己创建计时器、系统通知监听或音频文件管理逻辑。

## 阅读入口

先看 `FeishuMeetingCountdownApp.swift` 理解 SwiftUI / AppKit 双入口，再看 `MenuBarStatusItemController.swift`、`AppContainer.swift` 和 `AppRuntime.swift` 理解菜单栏安装与依赖装配；设置窗口链路则先看 `SettingsView.swift` 这个壳层入口，再进入 `Settings/AGENTS.md` 和对应 tab 文件；最后看 `LaunchAtLoginController.swift` 与 `AppRefreshController.swift`。

## 开发注意事项

- 这里的 View 和状态栏控制器都应保持薄，不要把“下一场会议选择规则”重新写一遍。
- 系统事件监听、登录项切换、提醒音频列表管理、菜单栏渲染时钟、状态栏按钮外观和刷新节奏控制都属于壳层编排；真正的业务状态更新必须继续汇总回 `SourceCoordinator` 或对应控制器，不要让设置页直接驱动底层服务。
- SwiftUI 视图和依赖装配代码也要写学习导向的中文注释，尤其要解释属性包装器、场景声明和为什么动作要交给协调层。
- 设置窗口相关改动如果继续增长，优先落在 `Settings/` 子目录对应文件中；只有全局状态、壳层生命周期或文件导入入口才应回到 `SettingsView.swift`。
- `NSPopover` 安装 `NSHostingController` 时，不要为了取 `fittingSize` 手动调用 `layoutSubtreeIfNeeded()`；这会在 AppKit 正在布局宿主视图时触发递归布局警告。当前菜单弹层尺寸应优先走显式常量，而不是安装阶段的强制布局。
