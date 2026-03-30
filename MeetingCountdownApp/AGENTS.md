# AGENTS.md

## 模块名称

`MeetingCountdownApp`

## 模块目的

这是 macOS 客户端当前阶段的单一 app target 源码根目录，负责承载首版菜单栏应用骨架、统一会议域模型、数据源协调层和后续系统能力的落点。它本身不直接定义某一种具体接入方式的完整实现，而是先提供稳定的分层边界。

## 包含内容

- `AppShell/`：应用入口、菜单栏、设置窗口、依赖装配。
- `Domain/`：统一会议模型、连接模式、数据源协议、时间与选择规则。
- `SourceCoordinator/`：活动数据源切换、统一刷新入口、状态聚合。
- `Preferences/`：偏好模型与持久化接口骨架。
- `Diagnostics/`：诊断状态模型与诊断协议骨架。
- `Shared/`：跨模块共用工具，例如日志封装。

## 关键依赖

- SwiftUI
- Foundation
- Observation / Combine 风格状态发布能力
- 后续会接入的 EventKit、UserNotifications、AVFoundation、Keychain 封装

## 关键状态 / 数据流

当前主状态流是 `MeetingSource -> SourceCoordinatorState -> AppShell View`。任何未来接入方式都必须先产出统一的 `MeetingRecord`，再由 `SourceCoordinator` 计算当前健康状态、最近刷新时间和下一场会议，UI 不直接读取底层原始数据。

## 阅读入口

建议先读 `AppShell/FeishuMeetingCountdownApp.swift` 和 `SourceCoordinator/SourceCoordinator.swift`，再看 `Domain/` 里的统一模型，最后再看 `Preferences/` 与 `Diagnostics/` 的接口骨架。

## 开发注意事项

- 新增子目录时继续补自己的 `AGENTS.md`。
- 不要让 UI 直接依赖未来的 EventKit、OAuth 或 CLI 实现。
- 未来即使拆 Swift Package，也应先保持这里的领域模型命名稳定，避免频繁重命名扩散到所有接入模块。
- 这个目录下的核心 Swift 文件默认要求函数级中文注释；注释目标读者包含“不熟悉 Swift 的人”，目标密度约为每 `8` 到 `10` 行有效代码至少有 `1` 行高信息量注释。
