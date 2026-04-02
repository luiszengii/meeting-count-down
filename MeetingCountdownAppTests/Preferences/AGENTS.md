# AGENTS.md

## 模块名称

`MeetingCountdownAppTests/Preferences`

## 模块目的

验证非敏感偏好与提醒音频列表是否稳定，当前重点是系统日历选择、提醒偏好、提醒音频列表和当前选中音频的持久化，以及音频列表控制器的导入 / 删除 / 切换行为。

## 包含内容

- `PreferencesStoreTests.swift`
- `SoundProfileLibraryControllerTests.swift`

## 关键依赖

- XCTest
- `Preferences`

## 关键状态 / 数据流

测试围绕 `UserDefaultsPreferencesStore`、`InMemoryPreferencesStore` 和音频列表控制器的读写契约，确认 app 重启后能恢复选中的系统日历、提醒偏好与当前提醒音频，并能正确维护已上传音频列表。

## 阅读入口

先看 `PreferencesStoreTests.swift`，再看 `SoundProfileLibraryControllerTests.swift`。

## 开发注意事项

- `UserDefaults` 测试必须使用隔离的 suite name，避免污染开发环境里的真实偏好。
- 断言不仅要看写入值，还要看 bootstrap 读取逻辑是否回到相同结果。
- 音频列表控制器测试优先用 stub 资产存储和 stub 试听播放器，不要在单元测试里真的复制文件或调用系统音频输出。
