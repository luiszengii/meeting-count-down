import AppKit
import SwiftUI

/// 概览页已从 SettingsView extension 迁移为独立 struct，实现 SettingsPage 协议。
/// 这样概览页可以拥有独立生命周期，新增页面不再需要修改 SettingsView 的枚举和 switch 分支。
///
/// 详见 ADR: docs/adrs/2026-04-22-settings-page-registry.md
struct OverviewPage: SettingsPage {
    @ObservedObject var sourceCoordinator: SourceCoordinator
    @ObservedObject var systemCalendarConnectionController: SystemCalendarConnectionController
    @ObservedObject var reminderEngine: ReminderEngine
    @ObservedObject var reminderPreferencesController: ReminderPreferencesController
    @ObservedObject var soundProfileLibraryController: SoundProfileLibraryController

    /// 跨页导航回调：点击"去日历"等按钮后由 SettingsView 响应。
    let onNavigate: (SettingsTab) -> Void

    var id: SettingsTab { .overview }
    var titleKey: (chinese: String, english: String) { ("概览", "Overview") }

    @MainActor func body(uiLanguage: AppUILanguage) -> AnyView {
        AnyView(OverviewPageBody(page: self, uiLanguage: uiLanguage))
    }
}

// MARK: - Body view

/// 将实际的 SwiftUI body 分离到一个内部 View struct，
/// 以便 @State 属性包装器正常工作（协议方法不能持有 @State）。
private struct OverviewPageBody: View {
    let page: OverviewPage
    let uiLanguage: AppUILanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            overviewMeetingPanel
            overviewSupportPanels
            overviewSummaryGrid
            overviewIssuePanel
        }
    }

    // MARK: Localization shorthand

    private func L(_ chinese: String, _ english: String) -> String {
        localized(chinese, english, in: uiLanguage)
    }

    // MARK: Meeting panel

    /// 下一场会议仍然是概览页的主舞台。
    private var overviewMeetingPanel: some View {
        GlassPanel(cornerRadius: 32, padding: 22, overlayOpacity: 0.16) {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("下一场会议", "Next Meeting"))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.95))

                if let nextMeeting = page.sourceCoordinator.state.nextMeeting {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(nextMeeting.title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(3)

                        Text(localizedMeetingScheduleLine(for: nextMeeting))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.92))

                        Text(localizedMeetingCountdownHeadline(for: nextMeeting))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(overviewReminderLine(for: nextMeeting))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.84))
                            .fixedSize(horizontal: false, vertical: true)

                        overviewMeetingMetadata(for: nextMeeting)
                        overviewMeetingActions(for: nextMeeting)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("当前还没有待提醒的会议", "No Meeting Is Ready to Remind Yet"))
                            .font(.system(size: 20, weight: .bold, design: .rounded))

                        Text(localizedHealthStateSummary)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            activateTab(.calendar)
                        } label: {
                            Text(L("去检查日历连接", "Check Calendar Setup"))
                        }
                        .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                    }
                }
            }
        }
    }

    /// 下一场会的元信息压成两条事实。
    private func overviewMeetingMetadata(for meeting: MeetingRecord) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                overviewMeetingMetaFact(
                    title: L("来源日历", "Calendar"),
                    value: meeting.source.displayName
                )
                overviewMeetingMetaFact(
                    title: L("会议类型", "Meeting Type"),
                    value: meeting.hasVideoConferenceLink
                        ? L("视频会议", "Video Meeting")
                        : L("普通事件", "Calendar Event")
                )
            }
            .frame(minWidth: 700, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                overviewMeetingMetaFact(
                    title: L("来源日历", "Calendar"),
                    value: meeting.source.displayName
                )
                overviewMeetingMetaFact(
                    title: L("会议类型", "Meeting Type"),
                    value: meeting.hasVideoConferenceLink
                        ? L("视频会议", "Video Meeting")
                        : L("普通事件", "Calendar Event")
                )
            }
        }
    }

    private func overviewMeetingMetaFact(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(title)：")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 主操作收敛成单一主入口和同步按钮。
    private func overviewMeetingActions(for meeting: MeetingRecord) -> some View {
        let joinLink = preferredJoinLink(for: meeting)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                if let joinLink {
                    Button {
                        NSWorkspace.shared.open(joinLink.url)
                    } label: {
                        Text(localizedJoinActionTitle(for: meeting))
                    }
                    .buttonStyle(GlassPillButtonStyle(tone: .primary))
                }

                Button {
                    Task {
                        await page.sourceCoordinator.refresh(trigger: .manualRefresh)
                    }
                } label: {
                    Text(L("立即同步", "Sync Now"))
                }
                .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                .disabled(page.sourceCoordinator.state.isRefreshing)
            }
            .frame(minWidth: 520, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                if let joinLink {
                    Button {
                        NSWorkspace.shared.open(joinLink.url)
                    } label: {
                        Text(localizedJoinActionTitle(for: meeting))
                    }
                    .buttonStyle(GlassPillButtonStyle(tone: .primary))
                }

                Button {
                    Task {
                        await page.sourceCoordinator.refresh(trigger: .manualRefresh)
                    }
                } label: {
                    Text(L("立即同步", "Sync Now"))
                }
                .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                .disabled(page.sourceCoordinator.state.isRefreshing)
            }
        }
    }

    // MARK: Support panels

    /// 第二行：提醒状态 / 同步状态双卡。
    private var overviewSupportPanels: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                overviewDetailActionCard(
                    title: L("提醒状态", "Reminder Status"),
                    rows: [
                        (L("当前提醒", "Reminder"), localizedOverviewReminderStatusTitle),
                        (L("触发方式", "Trigger"), localizedOverviewTriggerModeTitle),
                        (L("倒计时", "Countdown"), effectiveCountdownDurationLine),
                        (L("音频播放", "Audio"), localizedOverviewAudioStatusTitle)
                    ],
                    actionTitle: L("调整提醒设置", "Adjust Reminder Settings")
                ) {
                    activateTab(.reminders)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                overviewDetailActionCard(
                    title: L("同步状态", "Sync Status"),
                    rows: [
                        (L("最近同步", "Last Sync"), localizedLastRefreshLine),
                        (L("同步结果", "Result"), localizedOverviewSyncResultTitle),
                        (L("数据来源", "Source"), L("CalDAV 单一路径", "CalDAV Only")),
                        (
                            L("生效日历", "Active Calendars"),
                            L(
                                "\(page.systemCalendarConnectionController.selectedCalendarIDs.count) 个日历",
                                "\(page.systemCalendarConnectionController.selectedCalendarIDs.count) calendar(s)"
                            )
                        )
                    ],
                    actionTitle: L("查看同步详情", "View Sync Details")
                ) {
                    activateTab(.advanced)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 560, alignment: .leading)

            VStack(alignment: .leading, spacing: 14) {
                overviewDetailActionCard(
                    title: L("提醒状态", "Reminder Status"),
                    rows: [
                        (L("当前提醒", "Reminder"), localizedOverviewReminderStatusTitle),
                        (L("触发方式", "Trigger"), localizedOverviewTriggerModeTitle),
                        (L("倒计时", "Countdown"), effectiveCountdownDurationLine),
                        (L("音频播放", "Audio"), localizedOverviewAudioStatusTitle)
                    ],
                    actionTitle: L("调整提醒设置", "Adjust Reminder Settings")
                ) {
                    activateTab(.reminders)
                }

                overviewDetailActionCard(
                    title: L("同步状态", "Sync Status"),
                    rows: [
                        (L("最近同步", "Last Sync"), localizedLastRefreshLine),
                        (L("同步结果", "Result"), localizedOverviewSyncResultTitle),
                        (L("数据来源", "Source"), L("CalDAV 单一路径", "CalDAV Only")),
                        (
                            L("生效日历", "Active Calendars"),
                            L(
                                "\(page.systemCalendarConnectionController.selectedCalendarIDs.count) 个日历",
                                "\(page.systemCalendarConnectionController.selectedCalendarIDs.count) calendar(s)"
                            )
                        )
                    ],
                    actionTitle: L("查看同步详情", "View Sync Details")
                ) {
                    activateTab(.advanced)
                }
            }
        }
    }

    // MARK: Summary grid

    /// 四宫格：日历权限、生效日历、音频状态、应用状态。
    private var overviewSummaryGrid: some View {
        LazyVGrid(columns: responsiveCardColumns(minimum: 250, maximum: 340), spacing: 14) {
            overviewSummaryActionCard(
                title: L("日历权限", "Calendar Access"),
                value: localizedOverviewPermissionStatusTitle,
                detail: localizedOverviewPermissionDetail,
                accent: authorizationBadgeColor(for: page.systemCalendarConnectionController.authorizationState),
                actionTitle: L("管理权限", "Manage Permission")
            ) {
                openCalendarPrivacySettings()
            }

            overviewSummaryActionCard(
                title: L("生效日历", "Active Calendars"),
                value: localizedOverviewActiveCalendarsTitle,
                detail: localizedSelectedCalendarNamesDetail,
                accent: page.systemCalendarConnectionController.hasSelectedCalendars ? .green : .orange,
                actionTitle: L("选择日历", "Choose Calendars")
            ) {
                activateTab(.calendar)
            }

            overviewSummaryActionCard(
                title: L("音频状态", "Audio Status"),
                value: localizedOverviewAudioStatusTitle,
                detail: localizedOverviewAudioStatusDetail,
                accent: page.reminderPreferencesController.reminderPreferences.isMuted ? .orange : .blue,
                actionTitle: L("测试提醒音频", "Test Reminder Sound")
            ) {
                guard let selectedSoundProfile = page.soundProfileLibraryController.selectedSoundProfile else {
                    activateTab(.audio)
                    return
                }

                Task {
                    await page.soundProfileLibraryController.togglePreview(for: selectedSoundProfile.id)
                }
            }

            overviewSummaryActionCard(
                title: L("应用状态", "App Status"),
                value: localizedOverviewAppStatusTitle,
                detail: localizedOverviewAppStatusDetail,
                accent: overviewHealthBadgeColor,
                actionTitle: L("查看诊断信息", "View Diagnostics")
            ) {
                activateTab(.advanced)
            }
        }
    }

    // MARK: Issue panel

    private var overviewIssuePanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("最近发现的问题", "Recent Issues"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.94))

                Text(localizedOverviewIssueTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                Text(localizedOverviewIssueDetail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Card components

    /// 承接"提醒状态 / 同步状态"这种多行事实说明的卡片。
    private func overviewDetailActionCard(
        title: String,
        rows: [(String, String)],
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.94))

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { item in
                        overviewKeyValueRow(title: item.element.0, value: item.element.1)
                    }
                }

                Button(action: action) {
                    Text(actionTitle)
                }
                .buttonStyle(GlassPillButtonStyle(tone: .secondary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func overviewSummaryActionCard(
        title: String,
        value: String,
        detail: String,
        accent: Color,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        GlassPanel(cornerRadius: 24, padding: 16, overlayOpacity: 0.1) {
            VStack(alignment: .leading, spacing: 12) {
                Text(uiLanguage == .english ? title.uppercased() : title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent.opacity(0.82))

                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: action) {
                    Text(actionTitle)
                }
                .buttonStyle(GlassPillButtonStyle(tone: .secondary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func overviewKeyValueRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(title)：")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Navigation

    private func activateTab(_ tab: SettingsTab) {
        withAnimation(GlassMotion.page) {
            page.onNavigate(tab)
        }
    }

    // MARK: Presentation computed properties

    private func preferredJoinLink(for meeting: MeetingRecord) -> MeetingLink? {
        if let videoLink = meeting.links.first(where: { $0.kind == .vc }) {
            return videoLink
        }
        return meeting.links.first
    }

    private func localizedJoinActionTitle(for meeting: MeetingRecord) -> String {
        L(meeting.hasVideoConferenceLink ? "加入会议" : "打开事件",
          meeting.hasVideoConferenceLink ? "Join Video" : "Open Event")
    }

    private func localizedMeetingScheduleLine(for meeting: MeetingRecord) -> String {
        localizedDateHeadline(for: meeting.startAt)
    }

    private func localizedMeetingCountdownHeadline(for meeting: MeetingRecord) -> String {
        let interval = max(0, meeting.startAt.timeIntervalSinceNow)
        guard interval >= 60 else {
            return L("距离开始不到 1 分钟", "Starts in less than 1 minute")
        }
        return L(
            "距离开始还有 \(localizedFutureDurationDescription(interval))",
            "Starts in \(localizedFutureDurationDescription(interval))"
        )
    }

    private func overviewReminderLine(for meeting: MeetingRecord) -> String {
        switch page.reminderEngine.state {
        case let .scheduled(context):
            if isReminderContext(context, for: meeting) {
                return localizedScheduledReminderLine(for: context)
            }
        case let .playing(context, startedAt):
            if isReminderContext(context, for: meeting) {
                return L(
                    "已在 \(absoluteFormatter.string(from: startedAt)) 开始提醒，倒计时持续 \(context.countdownSeconds) 秒。",
                    "The reminder started at \(absoluteFormatter.string(from: startedAt)) and the countdown lasts \(context.countdownSeconds) seconds."
                )
            }
        case let .triggeredSilently(context, triggeredAt, reason):
            if isReminderContext(context, for: meeting) {
                switch reason {
                case .userMuted:
                    return L(
                        "已在 \(absoluteFormatter.string(from: triggeredAt)) 触发提醒，但当前是静音模式。",
                        "The reminder was triggered at \(absoluteFormatter.string(from: triggeredAt)), but mute mode is on."
                    )
                case .outputRoutePolicy:
                    return L(
                        "已在 \(absoluteFormatter.string(from: triggeredAt)) 触发提醒，但当前输出设备不会播放声音。",
                        "The reminder was triggered at \(absoluteFormatter.string(from: triggeredAt)), but the current audio output won't play sound."
                    )
                }
            }
        case .disabled:
            return L("当前已关闭本地提醒，这场会议不会触发提醒。", "Local reminders are turned off, so this meeting won't trigger a reminder.")
        case .failed(let message):
            return message
        case .idle:
            break
        }

        return L(
            "默认会在会议开始前 \(effectiveCountdownDurationLine) 触发提醒，倒计时持续 \(effectiveCountdownSeconds) 秒。",
            "By default, the reminder triggers \(effectiveCountdownDurationLine) before the meeting and the countdown lasts \(effectiveCountdownSeconds) seconds."
        )
    }

    private func isReminderContext(_ context: ScheduledReminderContext, for meeting: MeetingRecord) -> Bool {
        context.meeting.id == meeting.id && context.meeting.startAt == meeting.startAt
    }

    // MARK: Health & status strings

    private var localizedHealthStateSummary: String {
        switch page.sourceCoordinator.state.healthState {
        case .unconfigured:
            return L("还需要完成日历连接后才能开始提醒。", "Complete calendar setup before reminders can run.")
        case .ready:
            if page.sourceCoordinator.state.nextMeeting != nil {
                return L("当前无异常，下一场会议将按计划提醒。", "Everything is healthy. The next meeting will be reminded as planned.")
            }
            return L("当前无异常，正在等待新的会议。", "Everything is healthy. Waiting for the next meeting.")
        case .warning:
            return L("当前还能继续使用，但同步状态需要留意。", "The app is still usable, but sync needs attention.")
        case .failed:
            return page.sourceCoordinator.state.lastErrorMessage
                ?? L("当前无法读取会议。", "The app can't read meetings right now.")
        }
    }

    private var localizedOverviewReminderStatusTitle: String {
        page.reminderPreferencesController.reminderPreferences.globalReminderEnabled
            ? L("已开启", "Enabled") : L("已关闭", "Disabled")
    }

    private var localizedOverviewTriggerModeTitle: String {
        guard page.reminderPreferencesController.reminderPreferences.globalReminderEnabled else {
            return L("当前不会触发提醒", "No reminder will be triggered")
        }

        if let context = currentScheduledReminderContext {
            if context.triggeredImmediately {
                return L("已立即开始提醒", "Triggered immediately")
            }
            return L(
                "会前 \(localizedLeadTimeDescription(triggerAt: context.triggerAt, meetingStartAt: context.meeting.startAt))",
                "\(localizedLeadTimeDescription(triggerAt: context.triggerAt, meetingStartAt: context.meeting.startAt)) before start"
            )
        }

        return L("会前 \(effectiveCountdownDurationLine)", "\(effectiveCountdownDurationLine) before start")
    }

    private var currentScheduledReminderContext: ScheduledReminderContext? {
        switch page.reminderEngine.state {
        case let .scheduled(context),
             let .playing(context, _),
             let .triggeredSilently(context, _, _):
            return context
        case .idle, .disabled, .failed:
            return nil
        }
    }

    private var localizedOverviewAudioStatusTitle: String {
        if !page.reminderPreferencesController.reminderPreferences.globalReminderEnabled {
            return L("不会播放", "Playback Off")
        }
        if page.reminderPreferencesController.reminderPreferences.isMuted {
            return L("静音模式", "Muted")
        }
        if page.reminderPreferencesController.reminderPreferences.playSoundOnlyWhenHeadphonesConnected {
            return L("仅耳机播放", "Headphones Only")
        }
        return L("正常播放", "Audible")
    }

    private var localizedOverviewAudioStatusDetail: String {
        if !page.reminderPreferencesController.reminderPreferences.globalReminderEnabled {
            return L("本地提醒关闭后，不会播放提醒音频。", "Reminder audio won't play while local reminders are turned off.")
        }
        if page.reminderPreferencesController.reminderPreferences.isMuted {
            return L("提醒触发后仍会静默执行，不会播放声音。", "Reminders will still trigger silently, but no sound will play.")
        }
        if page.reminderPreferencesController.reminderPreferences.playSoundOnlyWhenHeadphonesConnected {
            return L("当前只会在耳机或私密输出设备上播放提醒音频。", "Reminder audio will play only on headphones or other private listening outputs.")
        }
        return L("当前未处于静音或播放策略拦截状态。", "The app isn't currently blocked by mute mode or playback policy.")
    }

    private var localizedLastRefreshLine: String {
        guard let lastRefreshAt = page.sourceCoordinator.state.lastRefreshAt else {
            return L("尚未刷新", "Not yet refreshed")
        }
        return absoluteFormatter.string(from: lastRefreshAt)
    }

    private var localizedOverviewSyncResultTitle: String {
        switch syncFreshnessStatus {
        case .passed: return L("成功", "Successful")
        case .warning: return L("需要留意", "Needs Attention")
        case .failed: return L("失败", "Failed")
        case .pending: return L("同步中", "Syncing")
        case .idle: return L("尚未同步", "Not Synced Yet")
        }
    }

    private var syncFreshnessStatus: DiagnosticCheckStatus {
        SyncFreshnessDiagnostic.status(
            lastSuccessfulRefreshAt: page.sourceCoordinator.state.lastRefreshAt,
            now: Date()
        )
    }

    // MARK: Calendar strings

    private var localizedOverviewPermissionStatusTitle: String {
        switch page.systemCalendarConnectionController.authorizationState {
        case .authorized: return L("已授权", "Granted")
        case .notDetermined: return L("等待授权", "Needs Access")
        case .denied: return L("已拒绝", "Denied")
        case .restricted: return L("受限", "Restricted")
        case .writeOnly: return L("仅写入", "Write-only")
        case .unknown: return L("未知", "Unknown")
        }
    }

    private var localizedOverviewPermissionDetail: String {
        switch page.systemCalendarConnectionController.authorizationState {
        case .authorized:
            return L("应用可以正常读取日历事件。", "The app can read calendar events normally.")
        case .notDetermined:
            return L("完成授权后，应用才能读取并提醒会议。", "The app needs calendar access before it can read and remind meetings.")
        case .denied:
            return L("请先在系统设置中允许访问日历。", "Allow calendar access in System Settings first.")
        case .restricted:
            return L("当前设备限制了日历访问权限。", "Calendar access is currently restricted by the device.")
        case .writeOnly:
            return L("当前只有写入权限，无法读取已有会议。", "The app only has write access, so it can't read existing meetings.")
        case .unknown:
            return L("当前还无法确认日历权限状态。", "The app can't confirm the calendar permission state right now.")
        }
    }

    private var localizedOverviewActiveCalendarsTitle: String {
        let count = page.systemCalendarConnectionController.selectedCalendarIDs.count
        if count == 0 {
            return L("尚未选择日历", "No Calendars Selected")
        }
        return L("已选择 \(count) 个日历", "\(count) Calendar(s) Selected")
    }

    private var localizedSelectedCalendarNamesDetail: String {
        let selectedIDs = page.systemCalendarConnectionController.selectedCalendarIDs
        let names = page.systemCalendarConnectionController.availableCalendars
            .filter { selectedIDs.contains($0.id) }
            .map(\.title)

        let displayNames = names.isEmpty ? [] : Array(names.prefix(3))

        guard !displayNames.isEmpty else {
            if selectedIDs.isEmpty {
                return L("当前还没有日历参与提醒。", "No calendars are currently participating in reminders.")
            }
            let count = selectedIDs.count
            let fallback = L("\(count) 个已保存日历", "\(count) saved calendar(s)")
            return L("当前参与提醒的日历：\(fallback)", "Calendars currently used for reminders: \(fallback)")
        }

        return L(
            "当前参与提醒的日历：\(displayNames.joined(separator: "、"))",
            "Calendars currently used for reminders: \(displayNames.joined(separator: ", "))"
        )
    }

    // MARK: App status strings

    private var localizedOverviewAppStatusTitle: String {
        switch page.sourceCoordinator.state.healthState {
        case .ready:
            return page.sourceCoordinator.state.nextMeeting == nil
                ? L("等待新的会议", "Waiting for Meetings")
                : L("等待下一场会议", "Waiting for the Next Meeting")
        case .unconfigured:
            return L("等待完成设置", "Setup Needed")
        case .warning:
            return L("同步需要留意", "Sync Needs Attention")
        case .failed:
            return L("需要修复读取问题", "Read Issue Detected")
        }
    }

    private var localizedOverviewAppStatusDetail: String {
        switch page.sourceCoordinator.state.healthState {
        case .ready:
            return L("所有关键检查均已通过。", "All key checks are currently passing.")
        case .unconfigured:
            return L("完成日历连接和授权后，系统才会开始提醒。", "The app will start reminding only after calendar setup and permission are complete.")
        case .warning:
            return L("提醒链路还能继续使用，但建议尽快检查同步。", "Reminders can still run, but it's a good idea to inspect sync soon.")
        case .failed:
            return page.sourceCoordinator.state.lastErrorMessage
                ?? L("当前无法确认下一场会议。", "The app can't confirm the next meeting right now.")
        }
    }

    private var overviewHealthBadgeColor: Color {
        if page.sourceCoordinator.state.isRefreshing { return .blue }
        switch page.sourceCoordinator.state.healthState {
        case .ready: return .green
        case .warning, .unconfigured: return .orange
        case .failed: return .red
        }
    }

    // MARK: Issue strings

    private var localizedOverviewIssueTitle: String {
        if let lastErrorMessage = page.sourceCoordinator.state.lastErrorMessage {
            return lastErrorMessage
        }
        if case .failed = page.reminderEngine.state {
            return L("提醒当前不可用", "Reminders are unavailable")
        }
        switch page.systemCalendarConnectionController.authorizationState {
        case .denied:
            return L("当前无法读取日历权限", "Calendar access is currently denied")
        case .restricted:
            return L("当前设备限制了日历访问", "Calendar access is restricted")
        default:
            break
        }
        switch syncFreshnessStatus {
        case .failed:
            return L("最近一次同步没有成功完成", "The latest sync did not finish successfully")
        case .warning:
            return L("最近一次同步有些偏旧", "The latest sync looks a little stale")
        case .idle, .pending, .passed:
            break
        }
        return L("当前无异常", "No Issues Right Now")
    }

    private var localizedOverviewIssueDetail: String {
        if page.sourceCoordinator.state.lastErrorMessage != nil {
            return L("建议先去\u{201C}高级\u{201D}查看诊断信息，再决定下一步处理方式。", "Open Advanced and inspect diagnostics before deciding what to do next.")
        }
        if case .failed = page.reminderEngine.state {
            return L("建议先去\u{201C}提醒\u{201D}页检查开关和倒计时设置，再到\u{201C}高级\u{201D}查看诊断信息。", "Check reminder settings first, then inspect diagnostics in Advanced.")
        }
        switch page.systemCalendarConnectionController.authorizationState {
        case .denied, .restricted, .writeOnly:
            return L("先修复日历权限后，会议读取和提醒才能恢复正常。", "Repair calendar access first so meeting reading and reminders can return to normal.")
        default:
            break
        }
        switch syncFreshnessStatus {
        case .failed, .warning:
            return L("可以先立即同步一次；如果问题持续，再去\u{201C}高级\u{201D}查看诊断信息。", "Try syncing again first. If the issue continues, inspect diagnostics in Advanced.")
        case .idle, .pending, .passed:
            break
        }
        return L("如果后续出现权限、同步或音频问题，这里会优先展示修复入口。", "If permission, sync, or audio issues appear later, this area will show the fastest recovery path first.")
    }

    // MARK: Duration & date helpers (private copies, avoid cross-type dependency)

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private var absoluteFormatter: DateFormatter { Self.absoluteFormatter }

    private var effectiveCountdownSeconds: Int {
        if let override = page.reminderPreferencesController.reminderPreferences.countdownOverrideSeconds, override > 0 {
            return override
        }
        if let profile = page.soundProfileLibraryController.selectedSoundProfile {
            return max(1, Int(ceil(profile.duration)))
        }
        return 1
    }

    private var effectiveCountdownDurationLine: String {
        localizedDurationLine(for: TimeInterval(effectiveCountdownSeconds))
    }

    private func localizedDurationLine(for duration: TimeInterval) -> String {
        let totalSeconds = max(1, Int(ceil(duration)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if uiLanguage == .english {
            if minutes == 0 { return "\(seconds)s" }
            if seconds == 0 { return "\(minutes)m" }
            return "\(minutes)m \(seconds)s"
        }
        if minutes == 0 { return "\(seconds) 秒" }
        if seconds == 0 { return "\(minutes) 分钟" }
        return "\(minutes) 分 \(seconds) 秒"
    }

    private func localizedFutureDurationDescription(_ interval: TimeInterval) -> String {
        let totalMinutes = max(1, Int(ceil(interval / 60)))
        if uiLanguage == .english {
            guard totalMinutes >= 60 else {
                return totalMinutes == 1 ? "1 minute" : "\(totalMinutes) minutes"
            }
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if minutes == 0 { return hours == 1 ? "1 hour" : "\(hours) hours" }
            return "\(hours) hours \(minutes) minutes"
        }
        guard totalMinutes >= 60 else { return "\(totalMinutes) 分钟" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(minutes) 分钟"
    }

    private func localizedLeadTimeDescription(triggerAt: Date, meetingStartAt: Date) -> String {
        localizedDurationLine(for: max(1, meetingStartAt.timeIntervalSince(triggerAt)))
    }

    private func localizedScheduledReminderLine(for context: ScheduledReminderContext) -> String {
        let leadTime = localizedLeadTimeDescription(triggerAt: context.triggerAt, meetingStartAt: context.meeting.startAt)
        if context.triggeredImmediately {
            return L(
                "距离会议已经太近，因此会立即开始提醒，倒计时持续 \(context.countdownSeconds) 秒。",
                "The meeting is too close, so the reminder starts immediately and the countdown lasts \(context.countdownSeconds) seconds."
            )
        }
        return L(
            "将在会议开始前 \(leadTime) 触发提醒，倒计时持续 \(context.countdownSeconds) 秒。",
            "The reminder will trigger \(leadTime) before the meeting and the countdown lasts \(context.countdownSeconds) seconds."
        )
    }

    private static let englishMonthSymbols = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    private func localizedDateHeadline(for date: Date) -> String {
        let timeLine = absoluteFormatter.string(from: date)
        let cal = Calendar.current
        if cal.isDateInToday(date) { return L("今天 \(timeLine)", "Today \(timeLine)") }
        if cal.isDateInTomorrow(date) { return L("明天 \(timeLine)", "Tomorrow \(timeLine)") }
        if cal.isDateInYesterday(date) { return L("昨天 \(timeLine)", "Yesterday \(timeLine)") }
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        if uiLanguage == .english {
            return "\(Self.englishMonthSymbols[max(0, min(11, month - 1))]) \(day), \(timeLine)"
        }
        let currentYear = cal.component(.year, from: Date())
        let year = cal.component(.year, from: date)
        if year == currentYear { return "\(month)月\(day)日 \(timeLine)" }
        return "\(year)年\(month)月\(day)日 \(timeLine)"
    }

    // MARK: Color helpers

    private func authorizationBadgeColor(for state: SystemCalendarAuthorizationState) -> Color {
        switch state {
        case .authorized: return .green
        case .notDetermined: return .orange
        case .denied, .restricted, .writeOnly: return .red
        case .unknown: return .secondary
        }
    }

    private func openCalendarPrivacySettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(settingsURL)
    }

    // MARK: Grid layout helper

    private func responsiveCardColumns(minimum: CGFloat, maximum: CGFloat = 360) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: 16, alignment: .topLeading)]
    }
}
