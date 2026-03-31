import Foundation

/// `MeetingSource` 统一抽象任何可提供会议列表的上游来源。
/// 协议故意从 Phase 0 开始就采用 `async` 形式，
/// 因为后续无论是 EventKit 读取、系统事件监听触发的重读，还是本地缓存恢复，都会天然涉及异步边界。
/// 这样可以避免未来接入真实实现时，为了补异步再大面积修改调用方。

enum MeetingSourceError: Error, Equatable, Sendable {
    /// 代表这一路源还没完成前置配置，例如还没选系统日历或还没授权读取权限。
    case notConfigured(message: String)
    /// 代表源本身暂时不可用，例如 EventKit 读取失败或系统能力异常。
    case unavailable(message: String)

    /// 把底层错误统一压成可直接展示给用户的文本，避免 UI 层再理解领域错误的细节。
    var userFacingMessage: String {
        switch self {
        case .notConfigured(let message), .unavailable(let message):
            message
        }
    }
}

/// 用统一枚举表达数据源当前的健康度，避免调用方依赖多个分散布尔值。
enum SourceHealthState: Equatable, Sendable {
    /// 还没接入完成，属于可恢复的“未开始”状态。
    case unconfigured(message: String)
    /// 当前状态健康，可以正常读取会议。
    case ready(message: String)
    /// 可以继续使用，但有需要提醒用户注意的退化条件。
    case warning(message: String)
    /// 当前无法正常工作，需要用户修复问题。
    case failed(message: String)

    /// 提供较长的说明文字，适合详情区域和设置页。
    var summary: String {
        switch self {
        case .unconfigured(let message),
             .ready(let message),
             .warning(let message),
             .failed(let message):
            message
        }
    }

    /// 提供短标签，适合菜单栏这种显示空间很紧张的地方。
    var shortLabel: String {
        switch self {
        case .unconfigured:
            "未配置"
        case .ready:
            "就绪"
        case .warning:
            "注意"
        case .failed:
            "失败"
        }
    }

    /// 提供和当前状态匹配的 SF Symbol 名称，统一图标语义。
    var symbolName: String {
        switch self {
        case .unconfigured:
            "slider.horizontal.3"
        case .ready:
            "checkmark.circle"
        case .warning:
            "exclamationmark.triangle"
        case .failed:
            "xmark.octagon"
        }
    }
}

/// 单次刷新结束后返回给协调层的完整快照。
struct SourceSyncSnapshot: Equatable, Sendable {
    /// 这次快照是由哪一路源产出的。
    var source: MeetingSourceDescriptor
    /// 本次刷新后返回的规范化会议列表。
    var meetings: [MeetingRecord]
    /// 刷新完成后的健康状态。
    var healthState: SourceHealthState
    /// 刷新完成时刻。
    var refreshedAt: Date
}

protocol MeetingSource: Sendable {
    /// 每个数据源都必须暴露自己的描述信息，方便协调层做日志、状态和 UI 展示。
    var descriptor: MeetingSourceDescriptor { get }

    /// 返回当前数据源在不做完整刷新前的健康状态。
    func healthState() async -> SourceHealthState
    /// 根据触发来源执行刷新，并返回统一的同步快照。
    func refresh(trigger: RefreshTrigger, now: Date) async throws -> SourceSyncSnapshot
}
