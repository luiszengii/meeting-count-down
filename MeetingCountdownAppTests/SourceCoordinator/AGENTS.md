# AGENTS.md

## 模块名称

`MeetingCountdownAppTests/SourceCoordinator`

## 模块目的

验证统一刷新入口和错误状态聚合是否按预期工作。

## 包含内容

- `SourceCoordinatorTests.swift`

## 关键依赖

- XCTest
- `SourceCoordinator`

## 关键状态 / 数据流

测试覆盖“给定固定数据源返回值时，协调层如何生成下一场会议和健康状态”。

## 阅读入口

先看 `SourceCoordinatorTests.swift`。

## 开发注意事项

- 尽量用固定时钟和可控 stub，避免让测试依赖真实时间流逝。
- 测试中的 stub、失败源、固定时钟和每个测试方法都要写中文注释，帮助读者顺着测试学习状态流。
