import Foundation

/// `ConnectionMode` 描述应用当前激活的主数据源类型。
/// 根据项目约束，任一时刻只允许一个主数据源驱动提醒调度，
/// 因此这个枚举既是设置项，也是 `SourceCoordinator` 选择具体实现的主键。
enum ConnectionMode: String, CaseIterable, Codable, Identifiable, Sendable {
    /// 通过飞书 CalDAV 同步到 macOS Calendar，再由应用只读系统日历。
    case caldavSystemCalendar
    /// 用户自建飞书应用，客户端本地直连 OAuth 与 Calendar API。
    case byoFeishuApp
    /// 用户手动导入 `.ics` 或其他离线会议快照。
    case offlineImport
    /// 利用本机已安装的 `lark-cli` 做辅助诊断或导入。
    case cliAssisted

    /// 让 SwiftUI 的 `ForEach` 和 Picker 能直接把连接模式当成稳定标识使用。
    var id: String { rawValue }

    /// 为 UI 层提供用户可读的显示名，避免视图里重复写 `switch`。
    var displayName: String {
        switch self {
        case .caldavSystemCalendar:
            "CalDAV / 系统日历"
        case .byoFeishuApp:
            "BYO Feishu App"
        case .offlineImport:
            "离线导入"
        case .cliAssisted:
            "lark-cli 辅助"
        }
    }
}
