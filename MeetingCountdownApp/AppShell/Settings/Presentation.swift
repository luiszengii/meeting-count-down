import AppKit
import SwiftUI

/// 这个文件集中放设置页展示态推导。
/// 它只做文案、本地化、颜色和轻量展示计算，不改变任何业务规则，
/// 让页面文件专注布局，减少“视图 + 文案 + 状态解释”混写。
extension SettingsView {
    func authorizationBadgeColor(for state: SystemCalendarAuthorizationState) -> Color {
        switch state {
        case .authorized:
            return .green
        case .notDetermined:
            return .orange
        case .denied, .restricted, .writeOnly:
            return .red
        case .unknown:
            return .secondary
        }
    }

    func diagnosticBadgeColor(for status: DiagnosticCheckStatus) -> Color {
        switch status {
        case .passed:
            return .green
        case .warning:
            return .orange
        case .failed:
            return .red
        case .idle, .pending:
            return .secondary
        }
    }

    func openCalendarPrivacySettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }

    static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var isReminderPreferenceEditingDisabled: Bool {
        reminderPreferencesController.isLoadingState || reminderPreferencesController.isSavingState
    }

    var isSoundProfileEditingDisabled: Bool {
        soundProfileLibraryController.isLoadingState
            || soundProfileLibraryController.isImportingState
            || soundProfileLibraryController.isApplyingState
    }

    var syncFreshnessStatus: DiagnosticCheckStatus {
        SyncFreshnessDiagnostic.status(
            lastSuccessfulRefreshAt: sourceCoordinator.state.lastRefreshAt,
            now: Date()
        )
    }

    var selectedCalendarDetailLine: String {
        if systemCalendarConnectionController.hasSelectedCalendars {
            return localized("这些日历会参与提醒。", "These calendars are used for reminders.")
        }

        return localized("还没有选中日历，所以不会提醒。", "No calendar is selected yet, so reminders won't run.")
    }

    var nextMeetingDetailLine: String {
        if let nextMeeting = sourceCoordinator.state.nextMeeting {
            return localizedMeetingStartLine(for: nextMeeting)
        }

        return localizedHealthStateSummary
    }

    var reminderStatusBadgeColor: Color {
        switch reminderEngine.state {
        case .disabled:
            return .secondary
        case .failed:
            return .red
        case .idle:
            return .orange
        case .scheduled:
            return .green
        case .playing, .triggeredSilently:
            return .blue
        }
    }

    var currentSoundProfileLine: String {
        if let selectedSoundProfile = soundProfileLibraryController.selectedSoundProfile {
            return "\(selectedSoundProfile.displayName) · \(localizedDurationLine(for: selectedSoundProfile.duration))"
        }

        return localized("默认提醒音效", "Default reminder sound")
    }

    var countdownFollowLine: String {
        if let selectedSoundProfile = soundProfileLibraryController.selectedSoundProfile {
            let durationLine = localizedDurationLine(for: selectedSoundProfile.duration)
            return localized("当前跟随 \(selectedSoundProfile.displayName)（\(durationLine)）。", "Currently follows \(selectedSoundProfile.displayName) (\(durationLine)).")
        }

        return localized("当前跟随默认提醒音效时长。", "Currently follows the default reminder sound length.")
    }

    /// 壳层语言影响设置页、菜单栏弹层与状态文案。
    var uiLanguage: AppUILanguage {
        reminderPreferencesController.reminderPreferences.interfaceLanguage
    }

    /// 语言切换只改展示文本，不触发业务层重算。
    var interfaceLanguageBinding: Binding<AppUILanguage> {
        Binding(
            get: { uiLanguage },
            set: { language in
                Task {
                    await reminderPreferencesController.setInterfaceLanguage(language)
                }
            }
        )
    }

    var hasAddedCalDAVAccount: Bool {
        systemCalendarConnectionController.availableCalendars.contains(where: \.isSuggestedByDefault)
            || systemCalendarConnectionController.hasSelectedCalendars
    }

    var isCalendarConfigurationComplete: Bool {
        hasAddedCalDAVAccount
            && systemCalendarConnectionController.authorizationState == .authorized
            && systemCalendarConnectionController.hasSelectedCalendars
    }

    var calendarConfigurationSummaryLine: String {
        if isCalendarConfigurationComplete {
            return localized("日历已经连好，可以开始提醒。", "Calendar setup is complete.")
        }

        return localized("按下面几步连好飞书日历。", "Follow these steps to connect Feishu Calendar.")
    }

    var localizedCalendarSelectionSummary: String {
        let count = systemCalendarConnectionController.selectedCalendarIDs.count

        if count == 0 {
            return localized("尚未选择系统日历", "No calendar selected")
        }

        return localized("已选 \(count) 个日历", "\(count) calendar(s) selected")
    }

    var localizedLastRefreshLine: String {
        guard let lastRefreshAt = sourceCoordinator.state.lastRefreshAt else {
            return localized("尚未刷新", "Not yet refreshed")
        }

        return Self.absoluteFormatter.string(from: lastRefreshAt)
    }

    var localizedSyncFreshnessSummary: String {
        guard let lastRefreshAt = sourceCoordinator.state.lastRefreshAt else {
            return localized("还没有读到本地日历。", "The app hasn't read your local calendar yet.")
        }

        let elapsed = Date().timeIntervalSince(lastRefreshAt)
        let elapsedDescription = localizedElapsedDescription(elapsed)

        if elapsed <= 10 * 60 {
            return localized("\(elapsedDescription)前更新过。", "Updated \(elapsedDescription) ago.")
        }

        return localized("上次更新是 \(elapsedDescription) 前。", "Last updated \(elapsedDescription) ago.")
    }

    var localizedSyncFreshnessBadgeText: String {
        switch syncFreshnessStatus {
        case .idle:
            return localized("未检查", "Idle")
        case .pending:
            return localized("检查中", "Checking")
        case .passed:
            return localized("正常", "Fresh")
        case .warning:
            return localized("偏旧", "Stale")
        case .failed:
            return localized("失败", "Failed")
        }
    }

    var localizedHealthStateSummary: String {
        switch sourceCoordinator.state.healthState {
        case .unconfigured:
            return localized("还没完成日历设置。", "Calendar setup is incomplete.")
        case .ready:
            return localized("一切正常，正在等待下一场会议。", "Everything looks good. Waiting for the next meeting.")
        case .warning:
            return localized("还能继续使用，但同步需要留意。", "Still usable, but sync needs attention.")
        case .failed:
            return sourceCoordinator.state.lastErrorMessage
                ?? localized("现在读不到会议。", "Can't read meetings right now.")
        }
    }

    var localizedReminderStateSummary: String {
        switch reminderEngine.state {
        case .idle:
            return localized("暂无提醒", "No active reminder")
        case let .scheduled(context):
            return localized("《\(context.meeting.title)》已安排提醒", "Reminder set for “\(context.meeting.title)”")
        case let .playing(context, _):
            if context.triggeredImmediately {
                return localized("《\(context.meeting.title)》已开始倒计时", "Countdown started for “\(context.meeting.title)”")
            }

            return localized("《\(context.meeting.title)》倒计时中", "Countdown running for “\(context.meeting.title)”")
        case let .triggeredSilently(context, _, reason):
            switch reason {
            case .userMuted:
                return localized("《\(context.meeting.title)》已静默提醒", "“\(context.meeting.title)” was triggered silently")
            case .outputRoutePolicy:
                return localized("《\(context.meeting.title)》未播放声音", "“\(context.meeting.title)” stayed silent")
            }
        case .disabled:
            return localized("提醒已关闭", "Reminders are off")
        case .failed:
            return localized("提醒异常", "Reminder error")
        }
    }

    var localizedReminderStateDetailLine: String {
        switch reminderEngine.state {
        case .idle:
            return localized("当前没有需要执行的提醒。", "There is no reminder to run right now.")
        case let .scheduled(context):
            return localized("\(Self.absoluteFormatter.string(from: context.triggerAt)) 触发，倒计时 \(context.countdownSeconds) 秒。", "Triggers at \(Self.absoluteFormatter.string(from: context.triggerAt)) with a \(context.countdownSeconds)-second countdown.")
        case let .playing(context, startedAt):
            if context.triggeredImmediately {
                return localized("已经来不及等待，所以在 \(Self.absoluteFormatter.string(from: startedAt)) 立即开始提醒。", "The meeting was too close, so the reminder started immediately at \(Self.absoluteFormatter.string(from: startedAt)).")
            }

            return localized("已在 \(Self.absoluteFormatter.string(from: startedAt)) 开始播放提醒。", "Reminder playback started at \(Self.absoluteFormatter.string(from: startedAt)).")
        case let .triggeredSilently(_, triggeredAt, reason):
            switch reason {
            case .userMuted:
                return localized("\(Self.absoluteFormatter.string(from: triggeredAt)) 已触发，但当前是静音模式。", "Triggered at \(Self.absoluteFormatter.string(from: triggeredAt)), but mute mode is on.")
            case .outputRoutePolicy(let routeName):
                return localized("\(Self.absoluteFormatter.string(from: triggeredAt)) 已触发，但“\(routeName)”不会播放声音。", "Triggered at \(Self.absoluteFormatter.string(from: triggeredAt)), but “\(routeName)” won't play sound.")
            }
        case .disabled:
            return localized("提醒已关闭，不会创建新的提醒。", "Reminders are off, so no new reminder will be created.")
        case .failed:
            return sourceCoordinator.state.lastErrorMessage
                ?? localized("提醒现在不可用。", "Reminders aren't working right now.")
        }
    }

    var localizedLaunchAtLoginStatusSummary: String {
        launchAtLoginController.statusSummary(for: uiLanguage)
    }

    func localizedAuthorizationSummary(for state: SystemCalendarAuthorizationState) -> String {
        switch state {
        case .authorized:
            return localized("已授权，可以读取日历。", "Access granted. Calendar can be read.")
        case .notDetermined:
            return localized("还没授予日历权限。", "Calendar access hasn't been granted yet.")
        case .denied:
            return localized("日历权限被拒绝，请去系统设置打开。", "Calendar access was denied. Turn it on in System Settings.")
        case .restricted:
            return localized("日历权限受限，暂时无法读取。", "Calendar access is restricted right now.")
        case .writeOnly:
            return localized("当前只能写入，不能读取日历。", "Write-only access is available, so events can't be read.")
        case .unknown:
            return localized("暂时无法确认日历权限状态。", "The Calendar permission state couldn't be confirmed.")
        }
    }

    func localizedAuthorizationBadgeText(for state: SystemCalendarAuthorizationState) -> String {
        switch state {
        case .authorized:
            return localized("已授权", "Granted")
        case .notDetermined:
            return localized("待授权", "Pending")
        case .denied, .restricted, .writeOnly:
            return localized("不可读", "Blocked")
        case .unknown:
            return localized("未知", "Unknown")
        }
    }

    func localizedCalendarSubtitle(for calendar: SystemCalendarDescriptor) -> String {
        let sourceTypeLabel = localizedCalendarSourceTypeLabel(calendar.sourceTypeLabel)

        if calendar.sourceTitle.isEmpty {
            return sourceTypeLabel
        }

        return "\(calendar.sourceTitle) · \(sourceTypeLabel)"
    }

    func localizedCalendarSourceTypeLabel(_ label: String) -> String {
        switch label {
        case "本地":
            return localized("本地", "Local")
        case "订阅":
            return localized("订阅", "Subscribed")
        case "生日":
            return localized("生日", "Birthdays")
        case "其他":
            return localized("其他", "Other")
        default:
            return label
        }
    }

    func localizedMeetingStartLine(for meeting: MeetingRecord) -> String {
        "\(Self.absoluteFormatter.string(from: meeting.startAt)) (\(localizedCountdownLine(until: meeting.startAt)))"
    }

    func localizedCountdownLine(until date: Date) -> String {
        let interval = max(0, date.timeIntervalSinceNow)

        if interval < 60 {
            return localized("即将开始", "Starting Soon")
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

    func localizedElapsedDescription(_ elapsed: TimeInterval) -> String {
        let totalMinutes = max(1, Int(elapsed / 60))

        if uiLanguage == .english {
            guard totalMinutes >= 60 else {
                return totalMinutes == 1 ? "1 minute" : "\(totalMinutes) minutes"
            }

            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if minutes == 0 {
                return hours == 1 ? "1 hour" : "\(hours) hours"
            }

            return "\(hours)h \(minutes)m"
        }

        guard totalMinutes >= 60 else {
            return "\(totalMinutes) 分钟"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if minutes == 0 {
            return "\(hours) 小时"
        }

        return "\(hours) 小时 \(minutes) 分钟"
    }

    /// `SoundProfile.durationLine` 仍然是偏业务层的文案，这里只负责外壳本地化显示。
    func localizedDurationLine(for duration: TimeInterval) -> String {
        let totalSeconds = max(1, Int(ceil(duration)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if uiLanguage == .english {
            if minutes == 0 {
                return "\(seconds)s"
            }

            if seconds == 0 {
                return "\(minutes)m"
            }

            return "\(minutes)m \(seconds)s"
        }

        if minutes == 0 {
            return "\(seconds) 秒"
        }

        if seconds == 0 {
            return "\(minutes) 分钟"
        }

        return "\(minutes) 分 \(seconds) 秒"
    }

    func localizedJoinActionTitle(for meeting: MeetingRecord) -> String {
        localized(meeting.hasVideoConferenceLink ? "加入会议" : "打开事件", meeting.hasVideoConferenceLink ? "Join Video" : "Open Event")
    }

    func responsiveCardColumns(minimum: CGFloat, maximum: CGFloat = 360) -> [GridItem] {
        [
            GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: 16, alignment: .topLeading)
        ]
    }

    func localized(_ chinese: String, _ english: String) -> String {
        uiLanguage == .english ? english : chinese
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case overview
    case calendar
    case reminders
    case audio
    case advanced

    var id: String { rawValue }

    func title(for language: AppUILanguage) -> String {
        switch self {
        case .overview:
            return language == .english ? "Overview" : "概览"
        case .calendar:
            return language == .english ? "Calendar" : "日历"
        case .reminders:
            return language == .english ? "Reminders" : "提醒"
        case .audio:
            return language == .english ? "Audio" : "音频"
        case .advanced:
            return language == .english ? "Advanced" : "高级"
        }
    }
}

extension AppUILanguage {
    /// 语言选项使用各自原生名字，避免用户找不到切换入口。
    var optionLabel: String {
        switch self {
        case .simplifiedChinese:
            return "中文"
        case .english:
            return "English"
        }
    }
}

/// 切换设置页 tab 时用轻微下移 + 淡入，避免内容硬切。
struct SettingsPageTransitionModifier: ViewModifier {
    let opacity: Double
    let offsetY: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: offsetY)
    }
}

extension AnyTransition {
    static var settingsPageSwap: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SettingsPageTransitionModifier(opacity: 0, offsetY: 8),
                identity: SettingsPageTransitionModifier(opacity: 1, offsetY: 0)
            ),
            removal: .opacity
        )
    }
}
