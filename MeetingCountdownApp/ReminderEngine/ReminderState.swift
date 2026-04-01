import Foundation

/// `ReminderMenuBarAlertPresentation` 描述提醒命中时菜单栏需要临时切换成什么可见样式。
/// 它故意只保留标题和图标名两个最小字段，避免提醒模块反向依赖 SwiftUI 或 AppKit。
struct ReminderMenuBarAlertPresentation: Equatable, Sendable {
    /// 菜单栏需要短时间显示的标题。
    let title: String
    /// 与标题配套的 SF Symbol 名称。
    let symbolName: String
    /// 当前是不是高优先级提醒态。
    /// AppShell 会用它决定菜单栏文字和图标是否需要额外加粗，避免平时倒计时和提醒命中态长得太像。
    let isHighPriority: Bool
}

/// `ReminderIdentity` 用来唯一标识“一次具体的提醒实例”。
/// 仅靠会议 ID 不足以区分同一个循环日程的不同实例，所以这里把开始时间也纳入主键。
struct ReminderIdentity: Equatable, Hashable, Sendable {
    /// 统一会议模型里的稳定事件 ID。
    let meetingID: String
    /// 这次实例真正对应的开始时间。
    let startAt: Date

    /// 从会议模型直接构造提醒主键，避免调用方重复拼接字段。
    init(meeting: MeetingRecord) {
        self.meetingID = meeting.id
        self.startAt = meeting.startAt
    }
}

/// `ScheduledReminderContext` 记录一条活动提醒最关键的上下文。
/// UI 只要拿到它，就能知道当前对应哪场会议、何时触发以及是不是因为已经太近而立即触发。
struct ScheduledReminderContext: Equatable, Sendable {
    /// 当前提醒锁定的会议。
    let meeting: MeetingRecord
    /// 会前真正命中提醒的绝对时间点。
    let triggerAt: Date
    /// 本次调度采用的倒计时秒数。
    let countdownSeconds: Int
    /// 如果音效时长已经长于剩余时间，就会在重算时立即触发。
    let triggeredImmediately: Bool

    /// 统一返回提醒实例的唯一主键，避免上层反复自己推导。
    var identity: ReminderIdentity {
        ReminderIdentity(meeting: meeting)
    }
}

/// `ReminderState` 是提醒引擎暴露给 UI 的只读状态。
/// 它有意不暴露底层 `Task` 或音频对象，只表达用户真正需要知道的事实。
enum ReminderState: Equatable, Sendable {
    /// 当前没有活动提醒，并附带一条解释文案。
    case idle(message: String)
    /// 已经为下一场会议安排好会前提醒。
    case scheduled(ScheduledReminderContext)
    /// 默认音效正在播放。
    case playing(context: ScheduledReminderContext, startedAt: Date)
    /// 提醒已经命中，但由于静音设置不会播放音效。
    case triggeredSilently(context: ScheduledReminderContext, triggeredAt: Date)
    /// 用户关闭了总提醒开关。
    case disabled
    /// 提醒链路本身发生错误。
    case failed(message: String)

    /// 给菜单栏和设置页提供一条简短摘要。
    var summary: String {
        switch self {
        case let .idle(message):
            return message
        case let .scheduled(context):
            return "已为《\(context.meeting.title)》安排提醒"
        case let .playing(context, _):
            if context.triggeredImmediately {
                return "已立即播放《\(context.meeting.title)》提醒"
            }

            return "正在播放《\(context.meeting.title)》提醒"
        case let .triggeredSilently(context, _):
            if context.triggeredImmediately {
                return "已静默立即命中《\(context.meeting.title)》提醒"
            }

            return "已静默命中《\(context.meeting.title)》提醒"
        case .disabled:
            return "提醒已关闭"
        case let .failed(message):
            return message
        }
    }

    /// 提供一条次级说明，帮助用户理解当前为什么会是这个状态。
    var detailLine: String {
        switch self {
        case .idle:
            return "当前没有活动提醒任务。"
        case let .scheduled(context):
            return "将于 \(Self.timeFormatter.string(from: context.triggerAt)) 触发，倒计时 \(context.countdownSeconds) 秒。"
        case let .playing(context, startedAt):
            if context.triggeredImmediately {
                return "距离会议已不足 \(context.countdownSeconds) 秒，因此在 \(Self.timeFormatter.string(from: startedAt)) 立即播放。"
            }

            return "已在 \(Self.timeFormatter.string(from: startedAt)) 开始播放默认提醒音效。"
        case let .triggeredSilently(context, triggeredAt):
            if context.triggeredImmediately {
                return "距离会议已不足 \(context.countdownSeconds) 秒，因此在 \(Self.timeFormatter.string(from: triggeredAt)) 立即静默命中。"
            }

            return "已在 \(Self.timeFormatter.string(from: triggeredAt)) 命中提醒，但当前为静音模式。"
        case .disabled:
            return "总提醒开关关闭后，不会创建任何本地提醒任务。"
        case .failed:
            return "提醒引擎没有成功建立或执行当前提醒。"
        }
    }

    /// 当前状态是否还对应一条活动提醒任务或刚刚命中的提醒。
    var activeIdentity: ReminderIdentity? {
        switch self {
        case let .scheduled(context),
             let .playing(context, _),
             let .triggeredSilently(context, _):
            return context.identity
        case .idle, .disabled, .failed:
            return nil
        }
    }

    /// 菜单栏是当前产品里最核心的可见提醒反馈之一。
    /// 这里把提醒命中时的临时标签抽成纯值计算，方便 AppShell 复用，也方便单测覆盖。
    func menuBarAlertPresentation() -> ReminderMenuBarAlertPresentation? {
        switch self {
        case .playing:
            return ReminderMenuBarAlertPresentation(
                title: "马上开会",
                symbolName: "exclamationmark.circle.fill",
                isHighPriority: true
            )

        case .triggeredSilently:
            return ReminderMenuBarAlertPresentation(
                title: "静音开会",
                symbolName: "bell.slash.circle.fill",
                isHighPriority: true
            )

        case .idle, .scheduled, .disabled, .failed:
            return nil
        }
    }

    /// 统一用于展示触发时间的短格式。
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
