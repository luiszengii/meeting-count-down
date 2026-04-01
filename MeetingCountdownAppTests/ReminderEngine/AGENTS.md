# AGENTS.md

## 模块名称

`MeetingCountdownAppTests/ReminderEngine`

## 模块目的

验证本地提醒调度、静音与去重规则是否稳定，确保提醒引擎不会因为后续 UI 或数据源改动而重复提醒或漏提醒。

## 包含内容

- `ReminderEngineTests.swift`

## 关键依赖

- XCTest
- `ReminderEngine`
- `Preferences`
- `Domain`

## 关键状态 / 数据流

测试围绕“给定某个下一场会议与提醒偏好，提醒引擎会建立什么任务、进入什么状态、是否播放音效”展开。

## 阅读入口

先看 `ReminderEngineTests.swift`。

## 开发注意事项

- 优先使用可控的假调度器和假音频引擎，不要让测试真的等待时间流逝或真的播放声音。
- 每个测试都要明确说明它锁定的是哪条提醒规则，例如“静音不播放”“同一会议只提醒一次”。
