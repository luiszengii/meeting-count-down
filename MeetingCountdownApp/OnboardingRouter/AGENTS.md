# AGENTS.md

## 模块名称

`MeetingCountdownApp/OnboardingRouter`

## 模块目的

这个目录预留给“首次启动引导 / 路由编排”能力。当前产品已经收敛成 CalDAV-only，而且首版引导文案、权限说明和目标日历选择仍主要落在 [AppShell](../AppShell/AGENTS.md) 的设置窗口里，因此这里暂时不承载实际 Swift 源文件，也不负责提醒调度或系统日历读取。

## 包含内容

- 当前仅保留本目录索引文档，用来说明该目录为什么存在以及为什么现在还是空目录。
- 如果后续把“首次启动一次性引导”从设置页中拆出来，新的路由状态、首启流程视图和失败提示协调逻辑再收口到这里。

## 关键依赖

- `AppShell`
- `SystemCalendarBridge`
- `SourceCoordinator`
- SwiftUI

## 关键状态 / 数据流

当前没有独立运行态。现阶段的首启路径仍是“用户打开设置窗口 -> 阅读 CalDAV 配置说明 -> 授权系统日历 -> 选择目标日历 -> 由 `SourceCoordinator` 开始读会并建立提醒”。如果未来真的拆出独立引导，这个目录才应该承接“首次启动状态机 / 引导页路由 / 失败重试入口”的壳层编排，而不是重复实现底层桥接逻辑。

## 阅读入口

先看 [AppShell/SettingsView.swift](../AppShell/SettingsView.swift) 了解当前实际引导入口，再看 [SystemCalendarBridge](../SystemCalendarBridge/AGENTS.md) 和 [SourceCoordinator](../SourceCoordinator/AGENTS.md)。

## 开发注意事项

- 在当前版本里，不要为了“形式上有 OnboardingRouter”而重新造一套和设置页并行的首启 UI。
- 如果未来恢复独立引导流，先更新本目录 `AGENTS.md`，再新增具体代码文件。
- 后续真正新增核心 Swift 文件时，继续遵守学习导向的中文注释规则。
