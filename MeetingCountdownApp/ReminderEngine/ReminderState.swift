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
    /// 当前这条 presentation 是否需要胶囊背景。
    /// 普通读会状态保持轻量文本；真正的倒计时和提醒命中态才加背景，方便做闪烁强调。
    let showsCapsuleBackground: Bool
    /// 当前这一帧是否需要切到红色强调态。
    /// 菜单栏视图会同时把图标、文字和胶囊背景切到红色系，形成统一闪烁反馈。
    let shouldHighlightRed: Bool
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

/// `SilentTriggerReason` 说明提醒为什么命中了却没有真正播放音频。
/// 这能帮助设置页和菜单栏把“用户主动静音”和“耳机输出策略拦截”区分开。
enum SilentTriggerReason: Equatable, Sendable {
    /// 用户自己打开了静音模式。
    case userMuted
    /// 当前启用了“仅耳机输出时播放”，但默认输出不满足策略要求。
    case outputRoutePolicy(routeName: String)
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
    case triggeredSilently(context: ScheduledReminderContext, triggeredAt: Date, reason: SilentTriggerReason)
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
                return "已为《\(context.meeting.title)》进入会前倒计时"
            }

            return "正在为《\(context.meeting.title)》执行会前倒计时"
        case let .triggeredSilently(context, _, reason):
            return silentSummary(for: context, reason: reason)
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
                return "距离会议已不足 \(context.countdownSeconds) 秒，因此在 \(Self.timeFormatter.string(from: startedAt)) 立即进入会前倒计时并播放当前提醒音频。"
            }

            return "已在 \(Self.timeFormatter.string(from: startedAt)) 开始执行会前倒计时；菜单栏会在最后阶段显示秒级倒计时，并播放当前提醒音频。"
        case let .triggeredSilently(context, triggeredAt, reason):
            return silentDetailLine(for: context, triggeredAt: triggeredAt, reason: reason)
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
             let .triggeredSilently(context, _, _):
            return context.identity
        case .idle, .disabled, .failed:
            return nil
        }
    }

    /// 菜单栏是当前产品里最核心的可见提醒反馈之一。
    /// 这里把提醒命中时的临时标签抽成纯值计算，方便 AppShell 复用，也方便单测覆盖。
    func menuBarAlertPresentation(at now: Date) -> ReminderMenuBarAlertPresentation? {
        switch self {
        case let .playing(context, _):
            return playingPresentation(for: context, at: now)

        case let .triggeredSilently(_, _, reason):
            return alertPresentation(for: reason)

        case .idle, .scheduled, .disabled, .failed:
            return nil
        }
    }

    /// 统一收拢静默命中的摘要文案。
    private func silentSummary(for context: ScheduledReminderContext, reason: SilentTriggerReason) -> String {
        switch reason {
        case .userMuted:
            if context.triggeredImmediately {
                return "已静默立即命中《\(context.meeting.title)》提醒"
            }

            return "已静默命中《\(context.meeting.title)》提醒"

        case .outputRoutePolicy:
            if context.triggeredImmediately {
                return "已因音频输出策略静默立即命中《\(context.meeting.title)》提醒"
            }

            return "已因音频输出策略静默命中《\(context.meeting.title)》提醒"
        }
    }

    /// 统一收拢静默命中的详细解释文案。
    private func silentDetailLine(
        for context: ScheduledReminderContext,
        triggeredAt: Date,
        reason: SilentTriggerReason
    ) -> String {
        let triggeredTime = Self.timeFormatter.string(from: triggeredAt)

        switch reason {
        case .userMuted:
            if context.triggeredImmediately {
                return "距离会议已不足 \(context.countdownSeconds) 秒，因此在 \(triggeredTime) 立即静默命中。"
            }

            return "已在 \(triggeredTime) 命中提醒，但当前为静音模式。"

        case .outputRoutePolicy(let routeName):
            if context.triggeredImmediately {
                return "距离会议已不足 \(context.countdownSeconds) 秒，因此在 \(triggeredTime) 立即命中提醒；但当前默认输出“\(routeName)”不满足仅耳机播放策略，所以未播放音频。"
            }

            return "已在 \(triggeredTime) 命中提醒；但当前默认输出“\(routeName)”不满足仅耳机播放策略，所以未播放音频。"
        }
    }

    /// 菜单栏高优先级标签同样区分静音原因，避免用户误以为只是打开了静音开关。
    private func alertPresentation(for reason: SilentTriggerReason) -> ReminderMenuBarAlertPresentation {
        switch reason {
        case .userMuted:
            return ReminderMenuBarAlertPresentation(
                title: "静音开会",
                symbolName: "bell.slash.circle.fill",
                isHighPriority: true,
                showsCapsuleBackground: true,
                shouldHighlightRed: false
            )

        case .outputRoutePolicy:
            return ReminderMenuBarAlertPresentation(
                title: "避免外放",
                symbolName: "speaker.slash.circle.fill",
                isHighPriority: true,
                showsCapsuleBackground: true,
                shouldHighlightRed: false
            )
        }
    }

    /// 播放型提醒在菜单栏里分成两个阶段：
    /// 会前倒计时阶段优先展示秒数；会议真正开始后，再切到会议标题本身。
    private func playingPresentation(
        for context: ScheduledReminderContext,
        at now: Date
    ) -> ReminderMenuBarAlertPresentation {
        let remainingInterval = context.meeting.startAt.timeIntervalSince(now)

        if remainingInterval > 0 {
            let remainingSeconds = max(1, Int(ceil(remainingInterval)))

            return ReminderMenuBarAlertPresentation(
                title: "\(remainingSeconds)s",
                symbolName: "timer.circle.fill",
                isHighPriority: true,
                showsCapsuleBackground: true,
                shouldHighlightRed: shouldHighlightCountdownRed(
                    at: now,
                    remainingSeconds: remainingSeconds
                )
            )
        }

        return ReminderMenuBarAlertPresentation(
            title: context.meeting.title,
            symbolName: "exclamationmark.circle.fill",
            isHighPriority: true,
            showsCapsuleBackground: true,
            shouldHighlightRed: false
        )
    }

    /// 最后 `10` 秒进入红色闪烁阶段：
    /// `10s ... 5s` 每秒一闪，`4s ... 1s` 每秒两闪。
    private func shouldHighlightCountdownRed(at now: Date, remainingSeconds: Int) -> Bool {
        guard remainingSeconds <= 10 else {
            return false
        }

        let period: TimeInterval = remainingSeconds <= 4 ? 0.5 : 1.0
        let remainder = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        return remainder < period / 2
    }

    /// 统一用于展示触发时间的短格式。
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
