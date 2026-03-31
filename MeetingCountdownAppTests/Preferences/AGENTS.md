# AGENTS.md

## 模块名称

`MeetingCountdownAppTests/Preferences`

## 模块目的

验证非敏感偏好持久化是否稳定，当前重点是系统日历选择和提醒偏好持久化。

## 包含内容

- `PreferencesStoreTests.swift`

## 关键依赖

- XCTest
- `Preferences`

## 关键状态 / 数据流

测试围绕 `UserDefaultsPreferencesStore` 和 `InMemoryPreferencesStore` 的读写契约，确认 app 重启后能恢复选中的系统日历。

## 阅读入口

先看 `PreferencesStoreTests.swift`。

## 开发注意事项

- `UserDefaults` 测试必须使用隔离的 suite name，避免污染开发环境里的真实偏好。
- 断言不仅要看写入值，还要看 bootstrap 读取逻辑是否回到相同结果。
