# AGENTS.md

## 模块名称

`AppShell`

## 模块目的

负责应用运行壳层：SwiftUI `App` 入口、菜单栏内容、设置窗口和依赖装配。它只消费聚合后的应用状态，不直接承担接入实现、系统权限读取或网络同步。

## 包含内容

- `FeishuMeetingCountdownApp.swift`：应用入口和场景定义。
- `AppContainer.swift`：组装默认依赖与 stub 数据源。
- `MenuBarContentView.swift`：菜单栏内容。
- `SettingsView.swift`：Phase 0 设置窗口占位。

## 关键依赖

- SwiftUI
- AppKit
- `SourceCoordinator`

## 关键状态 / 数据流

`AppShell` 从 `SourceCoordinator` 读取只读状态并触发显式动作，例如手动刷新、切换活动数据源、打开设置与退出应用。菜单栏标题和图标都应该从协调层状态派生，不在视图里重复实现业务规则。

## 阅读入口

先看 `FeishuMeetingCountdownApp.swift`，再看 `AppContainer.swift`，最后看两个 View 文件。

## 开发注意事项

- 这里的 View 应保持薄，不要把“下一场会议选择规则”重新写一遍。
- 未来接入系统事件监听时，优先把监听结果送进 `SourceCoordinator`，不要直接驱动界面状态。
- SwiftUI 视图和依赖装配代码也要写学习导向的中文注释，尤其要解释属性包装器、场景声明和为什么动作要交给协调层。
