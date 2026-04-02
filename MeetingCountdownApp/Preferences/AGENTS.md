# AGENTS.md

## 模块名称

`Preferences`

## 模块目的

负责承载非敏感用户偏好的模型、提醒音频列表、本地文件管理和设置页可直接消费的控制器。这里既定义“应该记住什么”，也负责把这些偏好与音频元数据稳定落到本地存储。

## 包含内容

- `ReminderPreferences.swift`：提醒相关偏好模型。
- `PreferencesStore.swift`：偏好读取与写入协议，以及 `UserDefaults` / 内存版实现。
- `ReminderPreferencesController.swift`：把提醒偏好的读写动作收口成设置页可复用的状态对象。
- `SoundProfile.swift`：提醒音频条目模型，描述内建音频和用户上传音频的最小元数据。
- `SoundProfileAssetStore.swift`：把用户音频复制到 app 自己管理的目录，并负责删除与 URL 解析。
- `SoundProfileLibraryController.swift`：把多次导入、切换当前音频、试听状态和删除动作收口成设置页状态对象。

## 关键依赖

- Foundation
- AVFoundation

## 关键状态 / 数据流

当前主状态流是 `PreferencesStore / SoundProfileAssetStore -> ReminderPreferencesController / SoundProfileLibraryController -> SettingsView / SourceCoordinator / ReminderEngine`。提醒偏好不仅影响音量相关行为，还会驱动“仅含视频会议信息”“跳过已拒绝会议”“倒计时覆盖秒数”和“仅耳机输出时播放”这些筛选与执行策略；当前选中的提醒音频也由这里持久化，提醒引擎会根据它决定正式播放内容和默认倒计时时长；最近一次成功刷新时间同样由这里统一保存。

## 阅读入口

先看 `ReminderPreferences.swift` 和 `SoundProfile.swift` 理解偏好与音频模型，再看 `PreferencesStore.swift` 与 `SoundProfileAssetStore.swift` 了解持久化和本地文件语义，最后看 `ReminderPreferencesController.swift` 与 `SoundProfileLibraryController.swift` 理解设置页如何发起异步保存、导入和重算。

## 开发注意事项

- 敏感信息不属于这里，未来 token 必须进入 Keychain 相关模块。
- 对偏好字段做新增时，先考虑它是否真的属于“提醒偏好”，不要把接入配置也堆到这个目录。
- 偏好默认值会直接影响首次启动体验；像“仅耳机输出时播放”这类容易误伤提醒触达率的策略，默认值必须写清楚为什么默认关闭。
- 用户上传音频不能直接依赖原始选择路径；正式提醒只允许播放已经复制到 app 自己管理目录里的文件，否则重启后路径失效会让提醒无声失败。
- 对 `actor`、异步接口和默认值语义要补中文注释，帮助读者理解 Swift 并发和偏好模型设计。
