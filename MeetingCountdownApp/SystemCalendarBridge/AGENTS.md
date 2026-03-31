# AGENTS.md

## 模块名称

`SystemCalendarBridge`

## 模块目的

负责把 macOS `EventKit` 的系统日历能力桥接成应用可消费的统一状态与数据源，包括权限申请、系统日历枚举、日程事件读取、变化监听，以及把原始事件标准化成 `MeetingRecord`。

## 包含内容

- `SystemCalendarModels.swift`：权限状态、系统日历描述符和事件载荷模型。
- `SystemCalendarAccess.swift`：EventKit 访问协议与真实桥接实现。
- `SystemCalendarConnectionController.swift`：CalDAV 路线的配置状态、授权动作、日历多选与变化监听。
- `SystemCalendarMeetingSource.swift`：真正接入 `SourceCoordinator` 的系统日历数据源。

## 关键依赖

- EventKit
- Foundation
- `Domain`
- `Preferences`

## 关键状态 / 数据流

主流向是 `EventKit -> SystemCalendarAccess -> SystemCalendarConnectionController / SystemCalendarMeetingSource -> SourceCoordinator`。UI 不直接接触 `EKEvent`、`EKCalendar` 或 EventKit 权限枚举，而是读取这里定义的桥接状态。

## 阅读入口

先看 `SystemCalendarModels.swift` 了解桥接层对外暴露的稳定模型，再看 `SystemCalendarAccess.swift`，最后看控制器和真实数据源。

## 开发注意事项

- 不要把 EventKit 原始类型泄露到 `SettingsView` 或 `Domain`。
- 权限申请属于显式用户动作，不要在初始化或纯读取流程里自动弹系统权限框。
- 变化监听只能触发统一刷新入口，不要绕过 `SourceCoordinator` 直接改会议状态。
