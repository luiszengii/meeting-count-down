# AGENTS.md

## 模块名称

`MeetingCountdownAppTests/Domain`

## 模块目的

覆盖统一领域模型和规则的测试，确保未来新增接入方式时不会悄悄改变核心选择逻辑。

## 包含内容

- `NextMeetingSelectorTests.swift`

## 关键依赖

- XCTest
- `Domain` 层类型

## 关键状态 / 数据流

测试围绕规范化会议列表输入，验证下一场会议选择规则是否稳定。

## 阅读入口

先看 `NextMeetingSelectorTests.swift`。

## 开发注意事项

- 这里优先测纯规则，不要引入不必要的 UI 或系统依赖。
- 测试方法、测试数据构造函数和固定时间辅助函数默认都写中文注释，解释“这条断言在锁定什么规则”。
