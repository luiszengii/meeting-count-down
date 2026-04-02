# AGENTS.md

## 模块名称

`ReminderEngine`

## 模块目的

负责把“下一场会议”转换成真正的本地提醒行为。这个目录同时承载提醒状态模型、调度逻辑和默认音效播放封装，但不负责系统日历读取或 SwiftUI 视图渲染。

## 包含内容

- `ReminderState.swift`：提醒状态值类型，供菜单栏和设置页展示。
- `ReminderEngine.swift`：单一提醒调度入口，负责取消、重建和命中提醒。
- `ReminderAudioEngine.swift`：默认内建音效播放实现与抽象协议。
- `AudioOutputRoute.swift`：把 CoreAudio 默认输出设备压缩成“耳机 / 外放 / 未知”的最小提醒语义。
- `SelectableSoundProfileReminderAudioEngine.swift`：根据当前选中的提醒音频决定正式提醒真正播放什么。
- `SoundProfilePreviewPlayer.swift`：设置页专用的独立试听播放器。

## 关键依赖

- Foundation
- Combine
- AVFoundation
- CoreAudio
- `Preferences`
- `SourceCoordinator`

## 关键状态 / 数据流

当前主状态流是 `SourceCoordinatorState.nextMeeting + 当前选中提醒音频 -> ReminderEngine -> ReminderState -> AppShell View`。提醒引擎会把会议、提醒偏好、当前音频输出路由和当前选中的提醒音频一起折叠成最终执行策略：播放、静默触发、取消或保持既有调度。这里的“静默触发”仍然是提醒命中，只是因为静音或“仅耳机输出时播放”策略而跳过音频。

## 阅读入口

先看 `ReminderState.swift` 理解用户可见状态，再看 `ReminderEngine.swift` 的调度流程，随后看 `SelectableSoundProfileReminderAudioEngine.swift` 和 `SoundProfilePreviewPlayer.swift` 理解正式提醒与试听播放是如何分离的，再看 `AudioOutputRoute.swift` 理解耳机策略是如何做保守判断的。

## 开发注意事项

- 任何提醒都必须先经过 `ReminderEngine.reconcile`，不要让 UI 直接启动定时任务。
- 这里的状态机会频繁跨越 `Task`、`MainActor` 和取消语义，函数级中文注释要写清楚为什么这样取消和重建。
- 对输出设备的识别要保持保守，凡是无法安全断定为私密收听的场景，都应优先落到静默提醒而不是冒险外放。
- 设置页试听和正式提醒必须使用不同的播放器实例；否则用户在设置里试听时，很容易把正式提醒的播放状态和停止逻辑打乱。
- 默认音效是内建行为，不要把飞书账号、CalDAV 凭证或其它敏感信息混进这个目录。
