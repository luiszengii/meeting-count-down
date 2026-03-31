# AGENTS.md

## 模块名称

`MeetingCountdownAppTests/Diagnostics`

## 模块目的

验证接入前置检查的真实映射逻辑是否稳定，当前只覆盖系统日历权限状态的映射。

## 包含内容

- `DiagnosticCheckersTests.swift`

## 关键依赖

- XCTest
- EventKit
- `Diagnostics` 模块类型

## 关键状态 / 数据流

这些测试不关心 UI，而是锁定“机器事实如何被压成统一诊断状态”。

## 阅读入口

先看 `DiagnosticCheckersTests.swift`。

## 开发注意事项

- 优先锁定“系统原生权限枚举如何被压成应用诊断状态”这类稳定规则，不要把 UI 细节放进这里断言。
