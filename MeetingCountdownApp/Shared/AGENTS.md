# AGENTS.md

## 模块名称

`Shared`

## 模块目的

存放跨模块可复用、但又不属于某个具体业务域的轻量工具。当前阶段主要包含日志封装和本地 OAuth loopback 的固定配置。

## 包含内容

- `AppLogger.swift`
- `OAuthLoopbackConfiguration.swift`

## 关键依赖

- Foundation
- OSLog

## 关键状态 / 数据流

这里的工具不应持有业务状态，只为其他模块提供横切支持能力。

## 阅读入口

先看 `AppLogger.swift`，再看 `OAuthLoopbackConfiguration.swift`。

## 开发注意事项

- 只放真正跨模块的工具，避免把“暂时没想好放哪里”的代码都堆到这里。
- 即使是很小的共享工具，也要写解释性中文注释，说明为什么抽到共享层、线程语义是什么、调用方该如何理解它。
