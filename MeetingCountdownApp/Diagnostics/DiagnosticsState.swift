import Foundation

/// 这个文件负责沉淀“接入前置检查结果应该如何表达”。
/// 现在诊断的重点已经收敛到 CalDAV 主链路；设置页和后续健康页只需要理解
/// “系统日历权限是否允许继续”这一条关键事实，
/// 因此重点是把“检查状态”“用户文案”“是否阻塞后续路径”这些信息固化成结构化字段。

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

    /// 把枚举折叠成统一摘要，避免界面层再次写同一套 `switch`。
    /// `idle` 和 `pending` 也给默认文案，这样设置页第一次打开时不会出现空白。
    var summary: String {
        switch self {
        case .idle:
            return "尚未开始检查"
        case .pending:
            return "正在检查"
        case .passed(let message), .warning(let message), .failed(let message):
            return message
        }
    }

    /// 标记当前检查是否已经明确阻塞对应接入路径。
    /// Phase 1 的推荐逻辑只把 `failed` 当成硬阻塞；`warning` 仍允许用户继续理解该路径。
    var isBlocking: Bool {
        if case .failed = self {
            return true
        }

        return false
    }

    /// 给 UI 提供统一的视觉标签文本。
    /// 菜单栏和设置页都只消费这里的语义，避免不同界面对同一状态起不同名字。
    var badgeText: String {
        switch self {
        case .idle:
            return "未检查"
        case .pending:
            return "检查中"
        case .passed:
            return "通过"
        case .warning:
            return "注意"
        case .failed:
            return "阻塞"
        }
    }

    /// 给状态附一个稳定的 SF Symbol 名称，便于后续统一展示。
    var symbolName: String {
        switch self {
        case .idle, .pending:
            return "clock"
        case .passed:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .failed:
            return "xmark.octagon"
        }
    }
}

/// `DiagnosticItemDescriptor` 把原始状态包装成“可直接渲染的一行诊断项”。
/// 这样设置页不用知道字段名和标题映射，只要遍历 `items` 即可。
struct DiagnosticItemDescriptor: Identifiable, Equatable, Sendable {
    /// 使用固定 id，确保 SwiftUI 列表 diff 稳定。
    let id: String
    /// 面向用户展示的检查名称。
    let title: String
    /// 当前检查状态。
    let status: DiagnosticCheckStatus

    /// 直接代理状态摘要，减少视图层拼装工作。
    var summary: String {
        status.summary
    }
}

/// 统一收纳“当前应用接入前置检查”得到的快照。
/// 现在只保留 CalDAV 路线真正需要的系统日历权限检查。
struct DiagnosticsSnapshot: Equatable, Sendable {
    /// 系统日历权限检查结果，对 CalDAV / EventKit 路线最关键。
    var calendarPermission: DiagnosticCheckStatus

    /// `phaseZero` 表示还没有真正开始做任何检查时的默认状态。
    static let phaseZero = DiagnosticsSnapshot(
        calendarPermission: .idle
    )

    /// 把检查结果映射成一组可直接展示的诊断项。
    var items: [DiagnosticItemDescriptor] {
        [
            DiagnosticItemDescriptor(
                id: "calendar-permission",
                title: "系统日历权限",
                status: calendarPermission
            )
        ]
    }
}

/// `DiagnosticsProviding` 统一定义“当前这台机器的接入前置条件是什么”。
/// 这里刻意不把接入推荐规则放进协议里，因为推荐属于路由层职责，不属于探测层。
protocol DiagnosticsProviding: Sendable {
    /// 返回当前时刻所有诊断检查项的统一快照。
    /// 采用异步接口是为了给未来其他只读系统检查预留自然扩展位。
    func currentSnapshot() async -> DiagnosticsSnapshot
}

/// 统一抽象单项诊断检查器。
/// 这样真实 provider 可以并发运行多个检查，而测试也能只替换某一项检查器。
protocol DiagnosticChecking: Sendable {
    /// 运行一次单项诊断并返回标准化状态。
    func run() async -> DiagnosticCheckStatus
}

struct StubDiagnosticsProvider: DiagnosticsProviding {
    /// 保留 stub，方便单元测试或极早期启动态继续使用固定快照。
    func currentSnapshot() async -> DiagnosticsSnapshot {
        .phaseZero
    }
}
