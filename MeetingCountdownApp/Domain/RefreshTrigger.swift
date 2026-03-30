import Foundation

/// `RefreshTrigger` 统一描述“为什么现在要重读数据源”。
/// 这个枚举后续会被系统事件监听、手动刷新、网络恢复和睡眠唤醒共用，
/// 用它可以把刷新行为和触发来源一起保留下来，方便调试和日志归因。
enum RefreshTrigger: String, Equatable, Sendable {
    /// 应用刚启动时的首次刷新。
    case appLaunch
    /// 用户主动点击“立即刷新”。
    case manualRefresh
    /// macOS 从睡眠恢复后触发重读。
    case wakeFromSleep
    /// 网络从不可用恢复为可用后触发重读。
    case networkRestored
    /// 时区变化后触发时间重算。
    case timezoneChanged
    /// 用户切换了主数据源模式。
    case sourceChanged

    /// 提供面向 UI 或日志的人类可读名称，避免显示原始枚举名。
    var displayName: String {
        switch self {
        case .appLaunch:
            "应用启动"
        case .manualRefresh:
            "手动刷新"
        case .wakeFromSleep:
            "睡眠唤醒"
        case .networkRestored:
            "网络恢复"
        case .timezoneChanged:
            "时区变化"
        case .sourceChanged:
            "切换数据源"
        }
    }
}
