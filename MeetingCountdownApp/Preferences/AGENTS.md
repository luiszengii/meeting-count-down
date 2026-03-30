# AGENTS.md

## 模块名称

`Preferences`

## 模块目的

负责承载非敏感用户偏好的模型与持久化接口。Phase 0 先锁定接口和默认值，不急着接入真实存储实现。

## 包含内容

- `ReminderPreferences.swift`：提醒相关偏好模型。
- `PreferencesStore.swift`：偏好读取与写入协议，以及内存版占位实现。

## 关键依赖

- Foundation

## 关键状态 / 数据流

当前偏好状态还不直接驱动提醒引擎，但会作为后续设置页和调度逻辑的输入，默认由 `PreferencesStore` 异步读取。

## 阅读入口

先看 `ReminderPreferences.swift`，再看 `PreferencesStore.swift`。

## 开发注意事项

- 敏感信息不属于这里，未来 token 必须进入 Keychain 相关模块。
- 对偏好字段做新增时，先考虑它是否真的属于“提醒偏好”，不要把接入配置也堆到这个目录。
- 对 `actor`、异步接口和默认值语义要补中文注释，帮助读者理解 Swift 并发和偏好模型设计。
