# AGENTS.md

## 模块名称

`MeetingCountdownApp`

## 模块目的

这是 macOS 客户端当前阶段的单一 app target 源码根目录，负责承载首版菜单栏应用骨架、统一会议域模型、CalDAV / 系统日历桥接和提醒状态协调层。当前产品已经收敛成 CalDAV-only，所以这里的模块边界也围绕单一路径展开。

## 包含内容

- `AppShell/`：应用入口、菜单栏、设置窗口、依赖装配。
- `Domain/`：统一会议模型、数据源协议、时间与选择规则。
- `SourceCoordinator/`：CalDAV 主数据源的统一刷新入口、状态聚合。
- `ReminderEngine/`：本地提醒状态机、默认音效播放和调度封装。
- `Preferences/`：偏好模型与持久化接口骨架。
- `Diagnostics/`：系统日历权限相关的只读诊断状态与检查器。
- `Shared/`：跨模块共用工具，例如日志封装。

## 关键依赖

- SwiftUI
- Foundation
- Observation / Combine 风格状态发布能力
- EventKit
- AVFoundation

## 关键状态 / 数据流

当前主状态流已经收敛为 `EventKit -> SystemCalendarBridge -> MeetingSource -> SourceCoordinatorState -> ReminderEngine -> AppShell View`。任何系统日历原始事件都必须先转换成统一的 `MeetingRecord`，再由 `SourceCoordinator` 计算当前健康状态、最近刷新时间和下一场会议；提醒引擎只消费统一会议模型，UI 不直接读取底层原始数据或自己创建定时任务。

## 阅读入口

建议先读 `AppShell/FeishuMeetingCountdownApp.swift`、`SourceCoordinator/SourceCoordinator.swift` 和 `ReminderEngine/ReminderEngine.swift`，再看 `SystemCalendarBridge/` 与 `Diagnostics/`，最后再看 `Domain/` 里的统一模型和 `Preferences/`。

## 开发注意事项

- 新增子目录时继续补自己的 `AGENTS.md`。
- 不要让 UI 直接依赖 EventKit 原始类型或权限枚举。
- 未来即使拆 Swift Package，也应先保持这里的领域模型命名稳定，避免频繁重命名扩散到所有桥接模块。
- 这个目录下的核心 Swift 文件默认要求函数级中文注释；注释目标读者包含“不熟悉 Swift 的人”，目标密度约为每 `8` 到 `10` 行有效代码至少有 `1` 行高信息量注释。
