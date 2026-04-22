import AppKit
import SwiftUI

// MARK: - Residual presentation helpers (2026-04-22 split)
//
// 这个文件是 2026-04-22 拆分后的残余部分，包含：
//   • 跨页面通用的展示态推导（状态摘要、选择状态、日历过滤等）
//   • 文件级枚举 / 结构体（CalendarConnectionPresentationState、CalendarSourceGroup 等）
//
// 已迁出的内容：
//   • 徽章颜色 / 徽章文案        → SettingsBadgePresentation.swift
//   • Formatter + 日期时间格式化  → SettingsDateFormatting.swift
//   • 日历诊断快照构建            → CalendarConnectionDiagnosticsPresenter.swift
//   • localized() + 语言 Binding  → SettingsLocalizationPresentation.swift
//
// 详见 ADR: docs/adrs/2026-04-22-presentation-split.md

extension SettingsView {

    // MARK: Reminder editing guard flags

    var isReminderPreferenceEditingDisabled: Bool {
        reminderPreferencesController.loadingState || reminderPreferencesController.isSavingState
    }

    var isSoundProfileEditingDisabled: Bool {
        soundProfileLibraryController.loadingState
            || soundProfileLibraryController.isImportingState
            || soundProfileLibraryController.isApplyingState
    }

    // MARK: Sync freshness

    var syncFreshnessStatus: DiagnosticCheckStatus {
        SyncFreshnessDiagnostic.status(
            lastSuccessfulRefreshAt: sourceCoordinator.state.lastRefreshAt,
            now: Date()
        )
    }

    // MARK: Overview page strings

    /// 概览页头部不再强调"这是设置页"，而是强调"系统当前处于什么状态"。
    var localizedOverviewPageTitle: String {
        localized("会议提醒概览", "Meeting Reminder Overview")
    }

    var localizedOverviewPageSubtitle: String {
        localized(
            "管理日历连接、提醒状态、音频播放与同步健康度。",
            "Manage calendar connection, reminder status, audio playback, and sync health."
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

    // MARK: Sound / countdown line

    var currentSoundProfileLine: String {
        if let selectedSoundProfile = soundProfileLibraryController.selectedSoundProfile {
            return "\(selectedSoundProfile.displayName) · \(localizedDurationLine(for: selectedSoundProfile.duration))"
        }

        return localized("默认提醒音效", "Default reminder sound")
    }

    var selectedSoundProfileName: String {
        soundProfileLibraryController.selectedSoundProfile?.displayName
            ?? localized("默认提醒音效", "Default reminder sound")
    }

    /// 当前提醒链路仍然沿用"提前提醒时长 = 倒计时时长"的语义；
    /// 设置页只是把这条规则表达得更像可操作项，而不是长段说明文案。
    var isCountdownFollowingSelectedSound: Bool {
        reminderPreferencesController.reminderPreferences.countdownOverrideSeconds == nil
    }

    var countdownFollowLine: String {
        if !isCountdownFollowingSelectedSound {
            return localized(
                "当前倒计时固定为 \(effectiveCountdownDurationLine)，可在“提醒”页调整。",
                "Countdown is fixed at \(effectiveCountdownDurationLine). Adjust it in Reminders."
            )
        }

        if let selectedSoundProfile = soundProfileLibraryController.selectedSoundProfile {
            let durationLine = localizedDurationLine(for: selectedSoundProfile.duration)
            return localized("当前跟随 \(selectedSoundProfile.displayName)（\(durationLine)）。", "Currently follows \(selectedSoundProfile.displayName) (\(durationLine)).")
        }

        return localized("当前跟随默认提醒音效时长。", "Currently follows the default reminder sound length.")
    }

    // MARK: Reminder page strings

    var localizedReminderPageTitle: String {
        localized("提醒", "Reminders")
    }

    var localizedReminderPageSubtitle: String {
        localized(
            "只看提醒是否会执行、何时开始，以及声音会怎么处理。",
            "Focus on whether reminders will run, when they start, and how sound behaves."
        )
    }

    var localizedReminderStatusCardDetail: String {
        switch reminderEngine.state {
        case .idle:
            return localized("当前没有正在等待触发的提醒任务。", "There is no reminder waiting to trigger right now.")
        case let .scheduled(context):
            return localizedScheduledReminderLine(for: context)
        case let .playing(context, _):
            if context.triggeredImmediately {
                return localized("距离会议已经太近，因此提醒已经立即开始。", "The meeting was too close, so the reminder started immediately.")
            }

            return localized("提醒已经开始执行，菜单栏会继续显示倒计时。", "The reminder is already running and the menu bar keeps showing the countdown.")
        case let .triggeredSilently(_, _, reason):
            switch reason {
            case .userMuted:
                return localized("提醒已经命中，但当前为静音模式，因此不会播放声音。", "The reminder was triggered, but mute mode is on, so no sound will play.")
            case .outputRoutePolicy:
                return localized("提醒已经命中，但当前输出不满足播放策略，因此不会播放声音。", "The reminder was triggered, but the current output doesn't satisfy playback policy.")
            }
        case .disabled:
            return localized("本地提醒已关闭，因此不会为下一场会议建立提醒。", "Local reminders are off, so the next meeting won't get a reminder.")
        case .failed:
            return localized("提醒链路当前不可用，可能无法按计划触发。", "The reminder pipeline is unavailable right now, so it may not trigger as planned.")
        }
    }

    var localizedReminderScheduleSnapshotValue: String {
        switch reminderEngine.state {
        case .idle:
            return localized("暂无待触发", "Nothing Pending")
        case let .scheduled(context):
            let leadTime = localizedLeadTimeDescription(triggerAt: context.triggerAt, meetingStartAt: context.meeting.startAt)
            return localized("会前 \(leadTime)", "\(leadTime) before start")
        case let .playing(context, _):
            return context.triggeredImmediately
                ? localized("已立即开始", "Started Immediately")
                : localized("正在倒计时", "Countdown Running")
        case let .triggeredSilently(_, _, reason):
            switch reason {
            case .userMuted:
                return localized("静音命中", "Muted Trigger")
            case .outputRoutePolicy:
                return localized("策略静默", "Policy-muted")
            }
        case .disabled:
            return localized("提醒关闭", "Reminder Off")
        case .failed:
            return localized("当前不可用", "Unavailable")
        }
    }

    var localizedReminderLeadTimeSettingDetail: String {
        if isCountdownFollowingSelectedSound {
            return localized(
                "当前跟随 \(selectedSoundProfileName) 的时长；提醒和倒计时会一起开始。",
                "Currently follows \(selectedSoundProfileName); the reminder and countdown start together."
            )
        }

        return localized(
            "当前使用固定秒数；提醒和倒计时会一起开始。",
            "A fixed duration is active; the reminder and countdown start together."
        )
    }

    var localizedReminderCountdownModeValue: String {
        if isCountdownFollowingSelectedSound {
            return localized("跟随当前音频", "Follow Current Sound")
        }

        return localized("手动 \(effectiveCountdownDurationLine)", "Manual \(effectiveCountdownDurationLine)")
    }

    var localizedReminderCountdownModeDetail: String {
        if isCountdownFollowingSelectedSound {
            return localized(
                "当前用所选音频的时长决定会前提醒和倒计时。",
                "The selected sound duration currently decides both reminder lead time and countdown."
            )
        }

        return localized(
            "当前固定使用同一时长来触发提醒和执行倒计时。",
            "A fixed duration is currently used for both the reminder trigger and countdown."
        )
    }

    // MARK: Calendar configuration

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
        return localized(
            "最近一次同步成功于 \(localizedLastRefreshLine)（\(elapsedDescription)前）。",
            "The last successful sync finished at \(localizedLastRefreshLine) (\(elapsedDescription) ago)."
        )
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
            return localized("还需要完成日历连接后才能开始提醒。", "Complete calendar setup before reminders can run.")
        case .ready:
            if sourceCoordinator.state.nextMeeting != nil {
                return localized("当前无异常，下一场会议将按计划提醒。", "Everything is healthy. The next meeting will be reminded as planned.")
            }

            return localized("当前无异常，正在等待新的会议。", "Everything is healthy. Waiting for the next meeting.")
        case .warning:
            return localized("当前还能继续使用，但同步状态需要留意。", "The app is still usable, but sync needs attention.")
        case .failed:
            return sourceCoordinator.state.lastErrorMessage
                ?? localized("当前无法读取会议。", "The app can't read meetings right now.")
        }
    }

    var localizedReminderStateSummary: String {
        switch reminderEngine.state {
        case .idle:
            return localized("当前没有待触发的提醒", "No reminder is waiting to trigger")
        case .scheduled:
            return localized("下一次提醒已安排", "The next reminder is scheduled")
        case let .playing(context, _):
            if context.triggeredImmediately {
                return localized("提醒已立即开始执行", "The reminder started immediately")
            }

            return localized("提醒正在执行倒计时", "The reminder countdown is running")
        case let .triggeredSilently(_, _, reason):
            switch reason {
            case .userMuted:
                return localized("提醒已触发，但当前为静音模式", "The reminder was triggered, but mute mode is on")
            case .outputRoutePolicy:
                return localized("提醒已触发，但当前不会播放声音", "The reminder was triggered, but sound playback is blocked")
            }
        case .disabled:
            return localized("本地提醒已关闭", "Local reminders are turned off")
        case .failed:
            return localized("提醒当前不可用", "Reminders are currently unavailable")
        }
    }

    var localizedReminderStateDetailLine: String {
        switch reminderEngine.state {
        case .idle:
            return localized("当前没有正在等待触发的提醒任务。", "There is no reminder waiting to trigger right now.")
        case let .scheduled(context):
            return localizedScheduledReminderLine(for: context)
        case let .playing(context, startedAt):
            if context.triggeredImmediately {
                return localized(
                    "距离会议已经太近，因此在 \(Self.absoluteFormatter.string(from: startedAt)) 立即开始提醒，倒计时持续 \(context.countdownSeconds) 秒。",
                    "The meeting was too close, so the reminder started immediately at \(Self.absoluteFormatter.string(from: startedAt)) and will run for \(context.countdownSeconds) seconds."
                )
            }

            return localized(
                "已在 \(Self.absoluteFormatter.string(from: startedAt)) 开始提醒，当前倒计时持续 \(context.countdownSeconds) 秒。",
                "The reminder started at \(Self.absoluteFormatter.string(from: startedAt)) and the countdown lasts \(context.countdownSeconds) seconds."
            )
        case let .triggeredSilently(_, triggeredAt, reason):
            switch reason {
            case .userMuted:
                return localized(
                    "提醒已在 \(Self.absoluteFormatter.string(from: triggeredAt)) 触发，但当前是静音模式，因此不会播放声音。",
                    "The reminder was triggered at \(Self.absoluteFormatter.string(from: triggeredAt)), but mute mode is on, so no sound will play."
                )
            case .outputRoutePolicy(let routeName):
                return localized(
                    "提醒已在 \(Self.absoluteFormatter.string(from: triggeredAt)) 触发，但当前输出“\(routeName)”不满足播放策略，因此不会播放声音。",
                    "The reminder was triggered at \(Self.absoluteFormatter.string(from: triggeredAt)), but the current output “\(routeName)” doesn't satisfy the playback policy."
                )
            }
        case .disabled:
            return localized("本地提醒已关闭，因此不会为下一场会议创建新的提醒。", "Local reminders are turned off, so the next meeting won't get a new reminder.")
        case .failed:
            return sourceCoordinator.state.lastErrorMessage
                ?? localized("提醒当前不可用，可能无法按计划触发。", "Reminders are unavailable right now, so they may not trigger as planned.")
        }
    }

    var localizedLaunchAtLoginStatusSummary: String {
        launchAtLoginController.statusSummary(for: uiLanguage)
    }

    // MARK: Authorization summary helpers

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

    // MARK: Calendar page strings

    /// 日历页头部只保留一行事实摘要，不再堆满胶囊状态。
    var localizedCalendarPageStatusSummary: String {
        switch calendarConnectionState {
        case .authorizationRequired:
            return localized(
                "状态异常 · 无法访问日历 · 请先授予权限后重新检查",
                "Issue detected · Calendar access is blocked · Grant permission and check again"
            )
        case let .connectionFailure(message):
            return localized(
                "状态异常 · CalDAV 读取失败 · \(message)",
                "Issue detected · CalDAV read failed · \(message)"
            )
        case .healthy:
            if systemCalendarConnectionController.lastLoadedAt == nil {
                return localized(
                    "状态正常 · CalDAV 已连接 · 已授权 · 等待首次检查",
                    "Healthy · CalDAV connected · Access granted · Waiting for the first check"
                )
            }

            let checkSummary = calendarLastCheckedSummary
            return localized(
                "状态正常 · CalDAV 已连接 · 已授权 · \(checkSummary) 检查成功",
                "Healthy · CalDAV connected · Access granted · Checked successfully at \(checkSummary)"
            )
        }
    }

    /// "日历连接"模块会基于这份状态决定显示正常卡还是错误卡。
    var calendarConnectionState: CalendarConnectionPresentationState {
        let authorizationState = systemCalendarConnectionController.authorizationState

        guard authorizationState.allowsReading else {
            return .authorizationRequired
        }

        if case .failed = sourceCoordinator.state.healthState {
            let fallbackMessage = localized(
                "请检查网络、账号信息或服务器地址后重试",
                "Check your network, account information, or server address and try again"
            )
            return .connectionFailure(message: sourceCoordinator.state.lastErrorMessage ?? fallbackMessage)
        }

        if let errorMessage = systemCalendarConnectionController.errorMessage {
            return .connectionFailure(message: errorMessage)
        }

        return .healthy
    }

    /// "今天 17:27" 这种时间表达比单独的时分更清晰，跨天时也不会让用户误判。
    var calendarLastCheckedSummary: String {
        guard let lastLoadedAt = systemCalendarConnectionController.lastLoadedAt else {
            return localized("尚未完成首次检查", "No successful check yet")
        }

        return localizedDateHeadline(for: lastLoadedAt)
    }

    var localizedCalendarConnectionHeadline: String {
        switch calendarConnectionState {
        case .healthy:
            return localized(
                "飞书日历连接正常，可读取会议并用于提醒",
                "Feishu Calendar is connected and can be used for reminders"
            )
        case .authorizationRequired:
            return localized("无法访问日历", "Calendar Access Is Unavailable")
        case .connectionFailure:
            return localized("无法连接到飞书日历", "Unable to Connect to Feishu Calendar")
        }
    }

    var localizedCalendarConnectionDetail: String {
        switch calendarConnectionState {
        case .healthy:
            return localized(
                "当前连接方式为 CalDAV，系统日历读取正常。",
                "The app is using CalDAV and can read macOS Calendar normally."
            )
        case .authorizationRequired:
            return localized(
                "应用尚未获得日历访问权限，当前无法读取会议并触发提醒。",
                "The app doesn't have calendar access yet, so it can't read meetings or trigger reminders."
            )
        case let .connectionFailure(message):
            return message
        }
    }

    var localizedCalendarAuthorizationValue: String {
        switch systemCalendarConnectionController.authorizationState {
        case .authorized:
            return localized("已授权", "Granted")
        case .notDetermined:
            return localized("未授权", "Not Granted Yet")
        case .denied:
            return localized("已拒绝", "Denied")
        case .restricted:
            return localized("访问受限", "Restricted")
        case .writeOnly:
            return localized("仅写入", "Write-only")
        case .unknown:
            return localized("状态未知", "Unknown")
        }
    }

    var localizedCalendarSelectionCountSummary: String {
        localized(
            "已选择 \(systemCalendarConnectionController.selectedCalendarIDs.count) 个，共 \(systemCalendarConnectionController.availableCalendars.count) 个可用",
            "\(systemCalendarConnectionController.selectedCalendarIDs.count) selected, \(systemCalendarConnectionController.availableCalendars.count) available"
        )
    }

    // MARK: Calendar list helpers

    /// 搜索会保留来源分组，但匹配逻辑同时覆盖名称、来源和类型文案。
    var filteredCalendarSections: [CalendarSourceSection] {
        let query = calendarSearchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let calendars = systemCalendarConnectionController.availableCalendars.filter { calendar in
            guard !query.isEmpty else {
                return true
            }

            let candidates = [
                calendar.title,
                calendar.sourceTitle,
                localizedCalendarSourceTypeLabel(calendar.sourceTypeLabel),
                localizedCalendarGroupTitle(for: calendarSourceGroup(for: calendar))
            ]

            return candidates.contains { candidate in
                candidate.lowercased().contains(query)
            }
        }

        return CalendarSourceGroup.allCases.compactMap { group in
            let groupedCalendars = calendars.filter { calendarSourceGroup(for: $0) == group }
            guard !groupedCalendars.isEmpty else {
                return nil
            }

            return CalendarSourceSection(group: group, calendars: groupedCalendars)
        }
    }

    var calendarTitleDuplicateCounts: [String: Int] {
        Dictionary(
            systemCalendarConnectionController.availableCalendars.map { calendar in
                (
                    calendar.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    1
                )
            },
            uniquingKeysWith: +
        )
    }

    func localizedCalendarDisplayName(for calendar: SystemCalendarDescriptor) -> String {
        let normalizedTitle = calendar.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let duplicateCount = calendarTitleDuplicateCounts[normalizedTitle, default: 0]

        guard duplicateCount > 1 else {
            return calendar.title
        }

        let suffix = localizedCalendarDisambiguationSuffix(for: calendar)
        return localized("\(calendar.title)（\(suffix)）", "\(calendar.title) (\(suffix))")
    }

    func localizedCalendarDisambiguationSuffix(for calendar: SystemCalendarDescriptor) -> String {
        let sourceGroup = calendarSourceGroup(for: calendar)

        switch sourceGroup {
        case .feishu:
            return localized("飞书", "Feishu")
        case .iCloud:
            return "iCloud"
        case .subscribed:
            return localized("订阅", "Subscribed")
        case .other:
            if calendar.sourceTypeLabel == "生日" {
                return localized("生日", "Birthdays")
            }

            if !calendar.sourceTitle.isEmpty {
                return calendar.sourceTitle
            }

            return localizedCalendarSourceTypeLabel(calendar.sourceTypeLabel)
        }
    }

    func localizedCalendarSubtitle(for calendar: SystemCalendarDescriptor) -> String {
        let sourceTypeLabel = localizedCalendarSourceTypeLabel(calendar.sourceTypeLabel)

        if calendar.sourceTitle.isEmpty {
            return sourceTypeLabel
        }

        return "\(calendar.sourceTitle) · \(sourceTypeLabel)"
    }

    func localizedCalendarAccessoryTag(for calendar: SystemCalendarDescriptor) -> String? {
        if calendar.isSuggestedByDefault {
            return localized("主日历", "Primary")
        }

        if calendar.sourceTypeLabel == "生日" {
            return localized("生日", "Birthdays")
        }

        return nil
    }

    func localizedCalendarGroupTitle(for group: CalendarSourceGroup) -> String {
        switch group {
        case .feishu:
            return localized("飞书", "Feishu")
        case .iCloud:
            return "iCloud"
        case .subscribed:
            return localized("订阅日历", "Subscribed Calendars")
        case .other:
            return localized("其他", "Other")
        }
    }

    func calendarSourceGroup(for calendar: SystemCalendarDescriptor) -> CalendarSourceGroup {
        let normalizedSourceTitle = calendar.sourceTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalizedSourceTitle.contains("caldav.feishu.cn") || normalizedSourceTitle.contains("feishu") {
            return .feishu
        }

        switch calendar.sourceTypeLabel {
        case "iCloud":
            return .iCloud
        case "订阅":
            return .subscribed
        default:
            return .other
        }
    }

    var shouldShowCalendarPermissionAlert: Bool {
        !systemCalendarConnectionController.authorizationState.allowsReading
    }

    var shouldShowCalendarUnavailableAlert: Bool {
        systemCalendarConnectionController.authorizationState.allowsReading
            && !systemCalendarConnectionController.loadingState
            && systemCalendarConnectionController.availableCalendars.isEmpty
    }

    var shouldShowNoSelectedCalendarsAlert: Bool {
        systemCalendarConnectionController.authorizationState.allowsReading
            && !systemCalendarConnectionController.availableCalendars.isEmpty
            && systemCalendarConnectionController.selectedCalendarIDs.isEmpty
    }

    var shouldShowCalendarSaveFailureAlert: Bool {
        if case .failed = systemCalendarConnectionController.selectionPersistenceState {
            return true
        }

        return false
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

    func localizedJoinActionTitle(for meeting: MeetingRecord) -> String {
        localized(meeting.hasVideoConferenceLink ? "加入会议" : "打开事件", meeting.hasVideoConferenceLink ? "Join Video" : "Open Event")
    }

    // MARK: Scheduled reminder context

    /// Overview 里需要把当前提醒上下文抽出来判断是不是已经为下一场会议建好提醒。
    var currentScheduledReminderContext: ScheduledReminderContext? {
        switch reminderEngine.state {
        case let .scheduled(context),
             let .playing(context, _),
             let .triggeredSilently(context, _, _):
            return context
        case .idle, .disabled, .failed:
            return nil
        }
    }

    func isReminderContext(_ context: ScheduledReminderContext, for meeting: MeetingRecord) -> Bool {
        context.meeting.id == meeting.id && context.meeting.startAt == meeting.startAt
    }

    // MARK: Overview card strings

    var localizedOverviewReminderStatusTitle: String {
        reminderPreferencesController.reminderPreferences.globalReminderEnabled
            ? localized("已开启", "Enabled")
            : localized("已关闭", "Disabled")
    }

    var localizedOverviewTriggerModeTitle: String {
        guard reminderPreferencesController.reminderPreferences.globalReminderEnabled else {
            return localized("当前不会触发提醒", "No reminder will be triggered")
        }

        if let context = currentScheduledReminderContext {
            if context.triggeredImmediately {
                return localized("已立即开始提醒", "Triggered immediately")
            }

            return localized(
                "会前 \(localizedLeadTimeDescription(triggerAt: context.triggerAt, meetingStartAt: context.meeting.startAt))",
                "\(localizedLeadTimeDescription(triggerAt: context.triggerAt, meetingStartAt: context.meeting.startAt)) before start"
            )
        }

        return localized("会前 \(effectiveCountdownDurationLine)", "\(effectiveCountdownDurationLine) before start")
    }

    var localizedOverviewSyncResultTitle: String {
        switch syncFreshnessStatus {
        case .passed:
            return localized("成功", "Successful")
        case .warning:
            return localized("需要留意", "Needs Attention")
        case .failed:
            return localized("失败", "Failed")
        case .pending:
            return localized("同步中", "Syncing")
        case .idle:
            return localized("尚未同步", "Not Synced Yet")
        }
    }

    var localizedOverviewAudioStatusTitle: String {
        if !reminderPreferencesController.reminderPreferences.globalReminderEnabled {
            return localized("不会播放", "Playback Off")
        }

        if reminderPreferencesController.reminderPreferences.isMuted {
            return localized("静音模式", "Muted")
        }

        if reminderPreferencesController.reminderPreferences.playSoundOnlyWhenHeadphonesConnected {
            return localized("仅耳机播放", "Headphones Only")
        }

        return localized("正常播放", "Audible")
    }

    var localizedOverviewAudioStatusDetail: String {
        if !reminderPreferencesController.reminderPreferences.globalReminderEnabled {
            return localized("本地提醒关闭后，不会播放提醒音频。", "Reminder audio won't play while local reminders are turned off.")
        }

        if reminderPreferencesController.reminderPreferences.isMuted {
            return localized("提醒触发后仍会静默执行，不会播放声音。", "Reminders will still trigger silently, but no sound will play.")
        }

        if reminderPreferencesController.reminderPreferences.playSoundOnlyWhenHeadphonesConnected {
            return localized("当前只会在耳机或私密输出设备上播放提醒音频。", "Reminder audio will play only on headphones or other private listening outputs.")
        }

        return localized("当前未处于静音或播放策略拦截状态。", "The app isn't currently blocked by mute mode or playback policy.")
    }

    var localizedOverviewPermissionStatusTitle: String {
        switch systemCalendarConnectionController.authorizationState {
        case .authorized:
            return localized("已授权", "Granted")
        case .notDetermined:
            return localized("等待授权", "Needs Access")
        case .denied:
            return localized("已拒绝", "Denied")
        case .restricted:
            return localized("受限", "Restricted")
        case .writeOnly:
            return localized("仅写入", "Write-only")
        case .unknown:
            return localized("未知", "Unknown")
        }
    }

    var localizedOverviewPermissionDetail: String {
        switch systemCalendarConnectionController.authorizationState {
        case .authorized:
            return localized("应用可以正常读取日历事件。", "The app can read calendar events normally.")
        case .notDetermined:
            return localized("完成授权后，应用才能读取并提醒会议。", "The app needs calendar access before it can read and remind meetings.")
        case .denied:
            return localized("请先在系统设置中允许访问日历。", "Allow calendar access in System Settings first.")
        case .restricted:
            return localized("当前设备限制了日历访问权限。", "Calendar access is currently restricted by the device.")
        case .writeOnly:
            return localized("当前只有写入权限，无法读取已有会议。", "The app only has write access, so it can't read existing meetings.")
        case .unknown:
            return localized("当前还无法确认日历权限状态。", "The app can't confirm the calendar permission state right now.")
        }
    }

    var localizedOverviewActiveCalendarsTitle: String {
        let count = systemCalendarConnectionController.selectedCalendarIDs.count

        if count == 0 {
            return localized("尚未选择日历", "No Calendars Selected")
        }

        return localized("已选择 \(count) 个日历", "\(count) Calendar(s) Selected")
    }

    var localizedSelectedCalendarNamesDetail: String {
        let selectedNames = selectedCalendarDisplayNames

        guard !selectedNames.isEmpty else {
            return localized("当前还没有日历参与提醒。", "No calendars are currently participating in reminders.")
        }

        return localized(
            "当前参与提醒的日历：\(selectedNames.joined(separator: "、"))",
            "Calendars currently used for reminders: \(selectedNames.joined(separator: ", "))"
        )
    }

    var selectedCalendarDisplayNames: [String] {
        let selectedIDs = systemCalendarConnectionController.selectedCalendarIDs
        let names = systemCalendarConnectionController.availableCalendars
            .filter { selectedIDs.contains($0.id) }
            .map(\.title)

        if !names.isEmpty {
            return Array(names.prefix(3))
        }

        if selectedIDs.isEmpty {
            return []
        }

        return [localized("\(selectedIDs.count) 个已保存日历", "\(selectedIDs.count) saved calendar(s)")]
    }

    var localizedOverviewAppStatusTitle: String {
        switch sourceCoordinator.state.healthState {
        case .ready:
            return sourceCoordinator.state.nextMeeting == nil
                ? localized("等待新的会议", "Waiting for Meetings")
                : localized("等待下一场会议", "Waiting for the Next Meeting")
        case .unconfigured:
            return localized("等待完成设置", "Setup Needed")
        case .warning:
            return localized("同步需要留意", "Sync Needs Attention")
        case .failed:
            return localized("需要修复读取问题", "Read Issue Detected")
        }
    }

    var localizedOverviewAppStatusDetail: String {
        switch sourceCoordinator.state.healthState {
        case .ready:
            return localized("所有关键检查均已通过。", "All key checks are currently passing.")
        case .unconfigured:
            return localized("完成日历连接和授权后，系统才会开始提醒。", "The app will start reminding only after calendar setup and permission are complete.")
        case .warning:
            return localized("提醒链路还能继续使用，但建议尽快检查同步。", "Reminders can still run, but it's a good idea to inspect sync soon.")
        case .failed:
            return sourceCoordinator.state.lastErrorMessage
                ?? localized("当前无法确认下一场会议。", "The app can't confirm the next meeting right now.")
        }
    }

    var localizedOverviewIssueTitle: String {
        if let lastErrorMessage = sourceCoordinator.state.lastErrorMessage {
            return lastErrorMessage
        }

        if case .failed = reminderEngine.state {
            return localized("提醒当前不可用", "Reminders are unavailable")
        }

        switch systemCalendarConnectionController.authorizationState {
        case .denied:
            return localized("当前无法读取日历权限", "Calendar access is currently denied")
        case .restricted:
            return localized("当前设备限制了日历访问", "Calendar access is restricted")
        default:
            break
        }

        switch syncFreshnessStatus {
        case .failed:
            return localized("最近一次同步没有成功完成", "The latest sync did not finish successfully")
        case .warning:
            return localized("最近一次同步有些偏旧", "The latest sync looks a little stale")
        case .idle, .pending, .passed:
            break
        }

        return localized("当前无异常", "No Issues Right Now")
    }

    var localizedOverviewIssueDetail: String {
        if sourceCoordinator.state.lastErrorMessage != nil {
            return localized("建议先去“高级”查看诊断信息，再决定下一步处理方式。", "Open Advanced and inspect diagnostics before deciding what to do next.")
        }

        if case .failed = reminderEngine.state {
            return localized("建议先去“提醒”页检查开关和倒计时设置，再到“高级”查看诊断信息。", "Check reminder settings first, then inspect diagnostics in Advanced.")
        }

        switch systemCalendarConnectionController.authorizationState {
        case .denied, .restricted, .writeOnly:
            return localized("先修复日历权限后，会议读取和提醒才能恢复正常。", "Repair calendar access first so meeting reading and reminders can return to normal.")
        default:
            break
        }

        switch syncFreshnessStatus {
        case .failed, .warning:
            return localized("可以先立即同步一次；如果问题持续，再去“高级”查看诊断信息。", "Try syncing again first. If the issue continues, inspect diagnostics in Advanced.")
        case .idle, .pending, .passed:
            break
        }

        return localized("如果后续出现权限、同步或音频问题，这里会优先展示修复入口。", "If permission, sync, or audio issues appear later, this area will show the fastest recovery path first.")
    }

    // MARK: Grid layout helper

    func responsiveCardColumns(minimum: CGFloat, maximum: CGFloat = 360) -> [GridItem] {
        [
            GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: 16, alignment: .topLeading)
        ]
    }
}

// MARK: - File-level types

/// 日历页把"连接正常 / 权限异常 / 连接异常"抽成显式展示态，
/// 这样页面结构可以围绕任务组织，而不是把多种判断散在 View 里。
enum CalendarConnectionPresentationState: Equatable {
    case healthy
    case authorizationRequired
    case connectionFailure(message: String)
}

/// 日历列表按来源分组，帮助用户先理解"这些日历来自哪里"，再决定是否纳入提醒。
enum CalendarSourceGroup: String, CaseIterable, Identifiable {
    case feishu
    case iCloud
    case subscribed
    case other

    var id: String { rawValue }
}

/// 搜索后的结果仍然要保留分组顺序，因此用一个轻量 section 模型描述。
struct CalendarSourceSection: Identifiable, Equatable {
    let group: CalendarSourceGroup
    let calendars: [SystemCalendarDescriptor]

    var id: String { group.id }
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

/// `ReminderCountdownMode` 只服务于设置页表达"当前时长来自哪里"，
/// 它不会直接改变提醒引擎规则，只负责把现有偏好映射成两种可理解的 UI 选择。
enum ReminderCountdownMode: String, CaseIterable, Identifiable {
    case followSound
    case manual

    var id: String { rawValue }

    func title(for language: AppUILanguage) -> String {
        switch self {
        case .followSound:
            return language == .english ? "Follow Sound" : "跟随音频"
        case .manual:
            return language == .english ? "Manual" : "手动固定"
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
