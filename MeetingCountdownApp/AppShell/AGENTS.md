# AGENTS.md

## 模块名称

`AppShell`

## 模块目的

负责应用运行壳层：SwiftUI `App` 入口、菜单栏内容、设置窗口和依赖装配。它只消费聚合后的应用状态，不直接承担 EventKit 原始读取或系统日历配置细节。

## 包含内容

- `FeishuMeetingCountdownApp.swift`：应用入口和场景定义。
- `MenuBarStatusItemController.swift`：用 `NSStatusItem + NSPopover` 托管真正的菜单栏按钮和弹出内容。
- `SettingsSceneOpenController.swift`：把 SwiftUI 官方 `Settings` 打开动作桥接给 AppKit 菜单栏入口。
- `AppContainer.swift`：组装 CalDAV 主链路所需依赖。
- `AppRuntime.swift`：持有应用级长生命周期对象，避免控制器在 SwiftUI 场景切换时被释放。
- `MenuBarContentView.swift`：菜单栏弹出内容。
- `MenuBarPresentationClock.swift`：为菜单栏标签提供秒级倒计时和闪烁所需的受控时钟。
- `SettingsView.swift`：设置窗口，承载 CalDAV 配置、提醒偏好、提醒音频列表、刷新状态与健康信息。
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

`AppShell` 从 `SourceCoordinator`、`ReminderEngine`、`ReminderPreferencesController`、`SoundProfileLibraryController`、`LaunchAtLoginController` 和 `SystemCalendarConnectionController` 读取聚合状态，再把显式动作交回这些控制器或协调层。菜单栏秒级倒计时与最后 `10` 秒闪烁由 `MenuBarPresentationClock` 提供渲染时钟，但真正负责把菜单栏按钮安装到系统菜单栏的是 `MenuBarStatusItemController`；它只消费现成的 presentation，不重新推导提醒规则。菜单弹层里如果需要打开设置页，也必须先通过 `SettingsSceneOpenController` 登记 SwiftUI 官方 `openSettings` 动作，再由 AppKit 层复用，不能退回到旧的 selector 方式。真正的会议重读仍只能通过 `SourceCoordinator.refresh(trigger:)` 进入主链路，避免 View 自己创建计时器、系统通知监听或音频文件管理逻辑。

## 阅读入口

先看 `FeishuMeetingCountdownApp.swift` 理解 SwiftUI / AppKit 双入口，再看 `MenuBarStatusItemController.swift`、`AppContainer.swift` 和 `AppRuntime.swift` 理解菜单栏安装与依赖装配，最后看 `SettingsView.swift`、`LaunchAtLoginController.swift` 与 `AppRefreshController.swift`。

## 开发注意事项

- 这里的 View 和状态栏控制器都应保持薄，不要把“下一场会议选择规则”重新写一遍。
- 系统事件监听、登录项切换、提醒音频列表管理、菜单栏渲染时钟、状态栏按钮外观和刷新节奏控制都属于壳层编排；真正的业务状态更新必须继续汇总回 `SourceCoordinator` 或对应控制器，不要让设置页直接驱动底层服务。
- SwiftUI 视图和依赖装配代码也要写学习导向的中文注释，尤其要解释属性包装器、场景声明和为什么动作要交给协调层。
