import Foundation

/// `MenuBarPresentation` 是菜单栏按钮外观的纯值描述，
/// 由 `MenuBarPresentationCalculator` 根据当前聚合状态一次性计算得出。
/// AppKit 宿主层只需消费它，不再自己推导业务规则。
struct MenuBarPresentation: Equatable, Sendable {
    /// 菜单栏按钮当前应该显示的标题文本。
    let title: String
    /// 与标题配套的 SF Symbol 名称。
    let symbolName: String
    /// 当前按钮的视觉层级，影响文字粗细和胶囊背景色深浅。
    let visualState: MenuBarVisualState
    /// 当前是否处于高优先级提醒态，用于决定文字和图标是否需要额外加粗。
    let isHighPriority: Bool
    /// 当前是否需要胶囊形背景。
    let showsCapsuleBackground: Bool
    /// 当前帧是否应该切到红色闪烁强调态。
    let shouldHighlightRed: Bool
}

/// `MenuBarVisualState` 描述菜单栏按钮目前所处的三级视觉优先级。
enum MenuBarVisualState: Equatable, Sendable {
    /// 普通待命态：无即将会议，也无提醒命中。
    case idle
    /// 预热态：下一场会议在 30 分钟内。
    case meetingSoon
    /// 高优先级提醒态：提醒引擎命中，进入倒计时或已触发。
    case urgent
}

/// `MenuBarPresentationCalculator` 是把领域层状态翻译为菜单栏 presentation 的纯函数计算器。
/// 它不依赖 AppKit，不持有任何可变状态，可以安全地在任意 actor 上调用。
///
/// ## 设计原则
/// - 单一职责：只做"状态 → 外观描述"的翻译，不操作任何 UI 控件。
/// - 调用 `ReminderState.menuBarAlertPresentation(at:)` 获取提醒命中 presentation，
///   再叠加界面语言本地化，避免重新实现已有逻辑。
/// - 对 `SourceCoordinatorState` 的访问被限制在最小字段集，方便后续替换。
enum MenuBarPresentationCalculator {

    /// 根据当前聚合状态计算菜单栏按钮的完整外观描述。
    ///
    /// - Parameters:
    ///   - reminderState: 提醒引擎当前状态，是提醒 presentation 的唯一真值来源。
    ///   - sourceCoordinatorState: 会议读取层的聚合状态，用于普通态的倒计时和健康标签。
    ///   - now: 当前时刻，由调用方传入以确保外观帧一致。
    ///   - uiLanguage: 当前界面语言，用于本地化标题文案。
    /// - Returns: 菜单栏按钮本次渲染应该消费的完整外观描述。
    static func calculate(
        reminderState: ReminderState,
        sourceCoordinatorState: SourceCoordinatorState,
        now: Date,
        uiLanguage: AppUILanguage
    ) -> MenuBarPresentation {
        // 1. 优先检查提醒引擎命中态，把 ReminderState 作为 presentation 真值来源
        if let alertPresentation = localizedAlertPresentation(
            from: reminderState,
            at: now,
            uiLanguage: uiLanguage
        ) {
            return MenuBarPresentation(
                title: alertPresentation.title,
                symbolName: alertPresentation.symbolName,
                visualState: .urgent,
                isHighPriority: alertPresentation.isHighPriority,
                showsCapsuleBackground: alertPresentation.showsCapsuleBackground,
                shouldHighlightRed: alertPresentation.shouldHighlightRed
            )
        }

        // 2. 普通态：会议在 30 分钟内时进入预热胶囊态
        if let nextMeeting = sourceCoordinatorState.nextMeeting,
           nextMeeting.startAt.timeIntervalSince(now) <= 30 * 60 {
            return MenuBarPresentation(
                title: localizedMenuBarTitle(
                    sourceCoordinatorState: sourceCoordinatorState,
                    now: now,
                    uiLanguage: uiLanguage
                ),
                symbolName: sourceCoordinatorState.menuBarSymbolName,
                visualState: .meetingSoon,
                isHighPriority: false,
                showsCapsuleBackground: true,
                shouldHighlightRed: false
            )
        }

        // 3. 空闲态：无即将会议，按健康状态显示短标签
        return MenuBarPresentation(
            title: localizedMenuBarTitle(
                sourceCoordinatorState: sourceCoordinatorState,
                now: now,
                uiLanguage: uiLanguage
            ),
            symbolName: sourceCoordinatorState.menuBarSymbolName,
            visualState: .idle,
            isHighPriority: false,
            showsCapsuleBackground: false,
            shouldHighlightRed: false
        )
    }

    // MARK: - Private helpers

    /// 把 `ReminderState.menuBarAlertPresentation(at:)` 的结果本地化。
    /// `ReminderState` 是提醒 presentation 的唯一真值来源；这里只负责把标题文案按界面语言替换，
    /// 不重新推导任何业务规则（倒计时秒数、闪烁节奏等仍由 ReminderState 决定）。
    private static func localizedAlertPresentation(
        from reminderState: ReminderState,
        at now: Date,
        uiLanguage: AppUILanguage
    ) -> ReminderMenuBarAlertPresentation? {
        guard let base = reminderState.menuBarAlertPresentation(at: now) else {
            return nil
        }

        // 秒数型标题（"XXs"）是语言无关的，直接复用
        // 静音/外放型标题需要按界面语言替换
        let localizedTitle: String
        switch base.title {
        case "静音开会":
            localizedTitle = localized("静音开会", "Muted", uiLanguage: uiLanguage)
        case "避免外放":
            localizedTitle = localized("避免外放", "Private Audio", uiLanguage: uiLanguage)
        default:
            // 秒数倒计时、会议标题等保持原样
            localizedTitle = base.title
        }

        guard localizedTitle != base.title else {
            // 无需替换，直接返回原值，避免构造冗余副本
            return base
        }

        return ReminderMenuBarAlertPresentation(
            title: localizedTitle,
            symbolName: base.symbolName,
            isHighPriority: base.isHighPriority,
            showsCapsuleBackground: base.showsCapsuleBackground,
            shouldHighlightRed: base.shouldHighlightRed
        )
    }

    /// 普通/预热态的菜单栏标题：优先显示倒计时，否则退回健康状态短标签。
    private static func localizedMenuBarTitle(
        sourceCoordinatorState: SourceCoordinatorState,
        now: Date,
        uiLanguage: AppUILanguage
    ) -> String {
        if let nextMeeting = sourceCoordinatorState.nextMeeting {
            return localizedCountdownLine(until: nextMeeting.startAt, now: now, uiLanguage: uiLanguage)
        }

        switch sourceCoordinatorState.healthState {
        case .unconfigured:
            return localized("未配置", "Setup", uiLanguage: uiLanguage)
        case .ready:
            return localized("就绪", "Ready", uiLanguage: uiLanguage)
        case .warning:
            return localized("注意", "Warn", uiLanguage: uiLanguage)
        case .failed:
            return localized("失败", "Failed", uiLanguage: uiLanguage)
        }
    }

    /// 把目标开始时间转换成适合菜单栏空间的简洁倒计时文案。
    /// 会议开始前最后一分钟内逐秒显示 `Xs`，让用户在提醒真正命中前也能看到秒级倒计时；
    /// 超过一分钟则退回到分钟粒度，避免秒级跳动长期占用菜单栏宽度。
    private static func localizedCountdownLine(until date: Date, now: Date, uiLanguage: AppUILanguage) -> String {
        let interval = max(0, date.timeIntervalSince(now))

        if interval < 60 {
            let remainingSeconds = max(0, Int(interval.rounded(.up)))
            return "\(remainingSeconds)s"
        }

        let totalSeconds = Int(interval.rounded(.up))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if uiLanguage == .english {
            if hours > 0 {
                return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
            }

            return "\(max(1, minutes))m"
        }

        if hours > 0 {
            return minutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes) 分钟"
        }

        return "\(max(1, minutes)) 分钟"
    }

    /// 单行本地化辅助：把中英文候选文本按当前界面语言挑选出来。
    private static func localized(_ chinese: String, _ english: String, uiLanguage: AppUILanguage) -> String {
        uiLanguage == .english ? english : chinese
    }
}
