# AGENTS.md

## 模块名称

`ReminderEngine`

## 模块目的

负责把“下一场会议”转换成真正的本地提醒行为。这个目录同时承载提醒状态模型、调度逻辑和默认音效播放封装，但不负责系统日历读取或 SwiftUI 视图渲染。

## 包含内容

- `ReminderState.swift`：提醒状态值类型，供菜单栏和设置页展示。
- `ReminderEngine.swift`：单一提醒调度入口，负责取消、重建和命中提醒。
- `ReminderAudioEngine.swift`：默认内建音效播放实现与抽象协议。

## 关键依赖

- Foundation
- Combine
- AVFoundation
- `Preferences`
- `SourceCoordinator`

## 关键状态 / 数据流

当前主状态流是 `SourceCoordinatorState.nextMeeting -> ReminderEngine -> ReminderState -> AppShell View`。提醒引擎只消费统一会议模型和提醒偏好，不直接读取 EventKit，也不让视图直接碰 `Task.sleep` 或音频对象。

## 阅读入口

先看 `ReminderState.swift` 理解用户可见状态，再看 `ReminderEngine.swift` 的调度流程，最后看 `ReminderAudioEngine.swift` 如何优先播放 bundle 内的默认音效并在失败时降级。

## 开发注意事项

- 任何提醒都必须先经过 `ReminderEngine.reconcile`，不要让 UI 直接启动定时任务。
- 这里的状态机会频繁跨越 `Task`、`MainActor` 和取消语义，函数级中文注释要写清楚为什么这样取消和重建。
- 默认音效是内建行为，不要把飞书账号、CalDAV 凭证或其它敏感信息混进这个目录。
