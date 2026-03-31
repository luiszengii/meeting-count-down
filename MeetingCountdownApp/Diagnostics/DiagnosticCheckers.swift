import EventKit
import Foundation

/// 这个文件承载当前仍然保留的只读诊断检查器：系统日历权限。
/// 它只负责采样 CalDAV 主链路真正需要的系统事实，不主动弹权限框。

/// `DefaultDiagnosticsProvider` 负责把多项单独检查组合成一个统一快照。
/// 现在只负责读取系统日历权限，但仍保留统一 provider 形态，方便后续扩展其他只读健康检查。
struct DefaultDiagnosticsProvider: DiagnosticsProviding {
    /// CalDAV / EventKit 路线依赖的权限检查器。
    let calendarPermissionChecker: any DiagnosticChecking

    /// 默认使用真实系统实现；测试里也可以注入自定义检查器。
    init(
        calendarPermissionChecker: any DiagnosticChecking = SystemCalendarPermissionDiagnostic()
    ) {
        self.calendarPermissionChecker = calendarPermissionChecker
    }

    /// 读取当前系统日历权限并包装成统一快照。
    func currentSnapshot() async -> DiagnosticsSnapshot {
        return DiagnosticsSnapshot(
            calendarPermission: await calendarPermissionChecker.run()
        )
    }
}

/// `SystemCalendarPermissionDiagnostic` 只负责读取当前 EventKit 授权状态。
/// Phase 1 明确不在这里主动请求权限，因为“是否弹系统框”属于 Phase 2 的接入动作，不是诊断动作。
struct SystemCalendarPermissionDiagnostic: DiagnosticChecking {
    /// 允许测试注入固定授权状态，避免单元测试依赖当前机器权限。
    private let authorizationStatusProvider: @Sendable () -> EKAuthorizationStatus

    init(
        authorizationStatusProvider: @escaping @Sendable () -> EKAuthorizationStatus = {
            EKEventStore.authorizationStatus(for: .event)
        }
    ) {
        self.authorizationStatusProvider = authorizationStatusProvider
    }

    /// 把 EventKit 原生状态映射成应用自己的诊断语义。
    func run() async -> DiagnosticCheckStatus {
        switch authorizationStatusProvider() {
        case .fullAccess:
            return .passed(message: "系统日历权限已授权，可继续 CalDAV / 系统日历路线")
        case .writeOnly:
            return .failed(message: "系统日历当前只有写入权限，无法读取会议事件")
        case .notDetermined:
            return .warning(message: "系统日历权限尚未决定，进入 CalDAV 路线时再申请授权")
        case .restricted:
            return .failed(message: "系统日历权限受系统限制，当前无法读取 Calendar 数据")
        case .denied:
            return .failed(message: "系统日历权限已被拒绝，请先在系统设置里允许访问日历")
        @unknown default:
            return .warning(message: "无法确认系统日历权限状态，建议稍后重新检查")
        }
    }
}
