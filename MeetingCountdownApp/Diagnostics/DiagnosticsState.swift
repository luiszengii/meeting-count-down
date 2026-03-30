import Foundation

/// Phase 0 先把诊断状态的表达方式固定下来：
/// 每一项检查都应该能明确区分“尚未开始”“检查中”“通过”“警告”“失败”。
/// 未来接入向导和健康状态页都应该读取同一份结构，而不是自己拼接散乱的布尔值。

enum DiagnosticCheckStatus: Equatable, Sendable {
    /// 还没开始检查。
    case idle
    /// 正在检查中。
    case pending
    /// 检查通过，并附带解释文本。
    case passed(message: String)
    /// 检查没有完全失败，但存在需要提醒用户注意的问题。
    case warning(message: String)
    /// 检查失败，当前路径不可继续。
    case failed(message: String)
}

/// 统一收纳“当前应用接入前置检查”得到的快照。
/// 这里先只放最基础的三类检查，后续可以继续扩展 OAuth 配置、系统能力、token 状态等检查项。
struct DiagnosticsSnapshot: Equatable, Sendable {
    /// 系统日历权限检查结果，对 CalDAV / EventKit 路线最关键。
    var calendarPermission: DiagnosticCheckStatus
    /// 本地 OAuth loopback 回调端口检查结果，对 BYO Feishu App 路线关键。
    var loopbackPort: DiagnosticCheckStatus
    /// `lark-cli` 可用性检查结果，对辅助模式关键。
    var cliAvailability: DiagnosticCheckStatus

    /// `phaseZero` 表示还没有真正开始做任何检查时的默认状态。
    static let phaseZero = DiagnosticsSnapshot(
        calendarPermission: .idle,
        loopbackPort: .idle,
        cliAvailability: .idle
    )
}

protocol DiagnosticsProviding: Sendable {
    /// 返回当前时刻所有诊断检查项的统一快照。
    /// 采用异步接口是为了给未来权限检查、端口探测、CLI 调用预留自然扩展位。
    func currentSnapshot() async -> DiagnosticsSnapshot
}

struct StubDiagnosticsProvider: DiagnosticsProviding {
    /// Phase 0 阶段先返回固定占位值，目的是把协议和调用链先固定下来。
    func currentSnapshot() async -> DiagnosticsSnapshot {
        .phaseZero
    }
}
