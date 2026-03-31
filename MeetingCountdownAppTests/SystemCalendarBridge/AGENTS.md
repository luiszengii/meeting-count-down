# AGENTS.md

## 模块名称

`MeetingCountdownAppTests/SystemCalendarBridge`

## 模块目的

验证系统日历桥接层的纯业务行为，包括默认预选规则、CalDAV 配置控制器、事件标准化以及真实 `MeetingSource` 的健康状态与刷新结果。

## 包含内容

- `SystemCalendarBridgeTests.swift`

## 关键依赖

- XCTest
- `SystemCalendarBridge`
- `Preferences`
- `SourceCoordinator`

## 关键状态 / 数据流

测试围绕“给定某个授权状态、某批候选日历和某批事件载荷，桥接层会产出什么 UI 状态和什么会议模型”。

## 阅读入口

先看 `SystemCalendarBridgeTests.swift`。

## 开发注意事项

- 优先使用纯 Swift stub，不要让测试依赖真实 EventKit 权限或本机真实 Calendar 数据。
- 需要解释清楚每个测试锁定的是哪条 CalDAV 规则，而不只是“点一下能跑通”。
