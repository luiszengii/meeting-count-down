# AGENTS.md

## 模块名称

`MeetingCountdownAppTests`

## 模块目的

承载 app target 的单元测试，优先覆盖统一领域规则和协调层状态流。

## 包含内容

- `Domain/`：领域规则测试。
- `SourceCoordinator/`：协调层状态测试。
- `ReminderEngine/`：本地提醒调度、去重和静音规则测试。
- `Diagnostics/`：接入前置检查测试。
- `SystemCalendarBridge/`：系统日历桥接与 CalDAV 配置状态测试。

## 关键依赖

- XCTest
- `@testable import FeishuMeetingCountdown`

## 关键状态 / 数据流

测试优先验证“输入什么会议列表会选出什么下一场会议”“刷新或切换源后状态如何变化”，而不是 UI 像素级表现。

## 阅读入口

先看 `Domain/NextMeetingSelectorTests.swift`，再看 `ReminderEngine/ReminderEngineTests.swift` 与 `SystemCalendarBridge/SystemCalendarBridgeTests.swift`，最后看 `SourceCoordinator/SourceCoordinatorTests.swift`。

## 开发注意事项

- 新增测试子目录时也补对应 `AGENTS.md`。
- 如果测试需要时间相关断言，优先注入固定 `DateProviding`，不要直接依赖真实时钟。
- 测试代码也遵守学习导向注释规则：测试方法、测试数据构造函数和关键 stub 默认都应写中文注释，帮助读者理解为什么这样断言。
- 如果测试代码里出现 `async/await`、`actor`、`MainActor` 或协议 stub，默认需要把这些 Swift 语义也解释清楚，而不只写业务目的。
