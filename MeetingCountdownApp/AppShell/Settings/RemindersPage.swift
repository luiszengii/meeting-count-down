import SwiftUI

/// 提醒设置页已从 SettingsView extension 迁移为独立 struct，实现 SettingsPage 协议。
///
/// 详见 ADR: docs/adrs/2026-04-22-settings-page-registry.md
struct RemindersPage: SettingsPage {
    @ObservedObject var reminderEngine: ReminderEngine
    @ObservedObject var reminderPreferencesController: ReminderPreferencesController
    @ObservedObject var soundProfileLibraryController: SoundProfileLibraryController

    var id: SettingsTab { .reminders }
    var titleKey: (chinese: String, english: String) { ("提醒", "Reminders") }

    @MainActor func body(uiLanguage: AppUILanguage) -> AnyView {
        AnyView(RemindersPageBody(page: self, uiLanguage: uiLanguage))
    }
}

// MARK: - Body view

private struct RemindersPageBody: View {
    let page: RemindersPage
    let uiLanguage: AppUILanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            remindersHeroPanel
            reminderTimingPanel
            reminderPolicyPanel
            reminderEligibilityPanel
        }
    }

    // MARK: Localization shorthand

    private func localized(_ chinese: String, _ english: String) -> String {
        FeishuMeetingCountdown.localized(chinese, english, in: uiLanguage)
    }

    // MARK: Hero panel

    private var remindersHeroPanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.14) {
            VStack(alignment: .leading, spacing: 16) {
                pageIntro(
                    eyebrow: localized("当前状态", "STATUS"),
                    title: localized("提醒现在会怎么工作", "How reminders behave right now"),
                    detail: localized(
                        "这里只看提醒本身是否已排定、何时开始，以及声音会怎么处理。",
                        "This section focuses on reminder execution only: whether it is scheduled, when it starts, and how sound behaves."
                    )
                )

                reminderStatusSummaryCard

                if page.reminderPreferencesController.loadingState || page.reminderPreferencesController.isSavingState {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(localized("正在保存提醒设置…", "Saving reminder settings..."))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = page.reminderPreferencesController.errorMessage {
                    warningStrip(errorMessage)
                }
            }
        }
    }

    private var reminderStatusSummaryCard: some View {
        GlassCard(cornerRadius: 26, padding: 18, tintOpacity: 0.22) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    reminderStatusSummaryLeadingIcon
                    VStack(alignment: .leading, spacing: 14) {
                        reminderStatusSummaryCopy
                        reminderStatusSummaryFacts
                    }
                }
                .frame(minWidth: 760, alignment: .leading)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 14) {
                        reminderStatusSummaryLeadingIcon
                        reminderStatusSummaryCopy
                    }
                    reminderStatusSummaryFacts
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reminderStatusSummaryLeadingIcon: some View {
        ZStack {
            Circle()
                .fill(reminderStatusBadgeColor.opacity(0.14))
                .frame(width: 44, height: 44)
            Image(systemName: reminderStatusSymbolName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(reminderStatusBadgeColor)
        }
    }

    private var reminderStatusSummaryCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("提醒摘要", "Reminder Summary"))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(reminderStatusBadgeColor.opacity(0.9))
            Text(localizedReminderStateSummary)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(localizedReminderStatusCardDetail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reminderStatusSummaryFacts: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                statusSnapshotRow(title: localized("下一次提醒", "Next Reminder"), value: localizedReminderScheduleSnapshotValue)
                statusSnapshotRow(title: localized("声音策略", "Sound Policy"), value: localizedOverviewAudioStatusTitle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                statusSnapshotRow(title: localized("下一次提醒", "Next Reminder"), value: localizedReminderScheduleSnapshotValue)
                statusSnapshotRow(title: localized("声音策略", "Sound Policy"), value: localizedOverviewAudioStatusTitle)
            }
        }
    }

    // MARK: Timing panel

    private var reminderTimingPanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 14) {
                pageIntro(
                    eyebrow: localized("提醒时间", "TIMING"),
                    title: localized("把时间参数调成你想要的节奏", "Set the timing rhythm you want"),
                    detail: localized(
                        "当前提醒仍然会在倒计时开始时一起触发；这里只把它表达成更明确的设置项。",
                        "Reminders still trigger when the countdown begins; this section simply expresses that rule as clearer settings."
                    )
                )

                preferenceValueRow(
                    title: localized("提前提醒", "Reminder Lead Time"),
                    detail: localizedReminderLeadTimeSettingDetail,
                    value: effectiveCountdownDurationLine
                ) {
                    HStack(spacing: 10) {
                        Stepper("", value: manualCountdownSecondsBinding, in: 1 ... 300)
                            .labelsHidden()
                            .disabled(isCountdownFollowingSelectedSound || isReminderPreferenceEditingDisabled)

                        if isCountdownFollowingSelectedSound {
                            preferenceStateLabel(text: localized("跟随音频", "Sound-based"), color: .secondary)
                        } else {
                            preferenceStateLabel(text: localized("手动固定", "Manual"), color: .blue)
                        }
                    }
                    .opacity(isCountdownFollowingSelectedSound ? 0.62 : 1)
                }

                preferenceDivider

                preferenceValueRow(
                    title: localized("倒计时时长", "Countdown Duration"),
                    detail: localizedReminderCountdownModeDetail,
                    value: localizedReminderCountdownModeValue
                ) {
                    Picker("", selection: reminderCountdownModeBinding) {
                        ForEach(ReminderCountdownMode.allCases) { mode in
                            Text(mode.title(for: uiLanguage)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 232)
                    .disabled(isReminderPreferenceEditingDisabled)
                }
            }
        }
    }

    // MARK: Policy panel

    private var reminderPolicyPanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 14) {
                pageIntro(
                    eyebrow: localized("播放方式", "PLAYBACK"),
                    title: localized("声音提醒", "Sound Playback"),
                    detail: localized("决定提醒命中后会不会真的出声。", "Choose whether reminders should actually make sound when they trigger.")
                )

                preferenceToggleRow(
                    title: localized("启用本地提醒", "Enable Local Reminders"),
                    detail: localized("为选中的日历安排会前提醒。", "Schedule reminders for selected calendars."),
                    isOn: Binding(
                        get: { page.reminderPreferencesController.reminderPreferences.globalReminderEnabled },
                        set: { isEnabled in Task { await page.reminderPreferencesController.setGlobalReminderEnabled(isEnabled) } }
                    )
                )

                preferenceDivider

                preferenceToggleRow(
                    title: localized("静音模式", "Mute Mode"),
                    detail: localized("保留提醒，但不播放声音。", "Keep reminders on, but mute the sound."),
                    isOn: Binding(
                        get: { page.reminderPreferencesController.reminderPreferences.isMuted },
                        set: { isMuted in Task { await page.reminderPreferencesController.setMuted(isMuted) } }
                    )
                )

                preferenceDivider

                preferenceToggleRow(
                    title: localized("仅在耳机连接时播放", "Play Only on Headphones"),
                    detail: localized("外放时会自动静音。", "Sound stays silent when you're on speakers."),
                    isOn: Binding(
                        get: { page.reminderPreferencesController.reminderPreferences.playSoundOnlyWhenHeadphonesConnected },
                        set: { isEnabled in Task { await page.reminderPreferencesController.setPlaySoundOnlyWhenHeadphonesConnected(isEnabled) } }
                    )
                )
            }
        }
    }

    // MARK: Eligibility panel

    private var reminderEligibilityPanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 14) {
                pageIntro(
                    eyebrow: localized("会议过滤", "FILTERS"),
                    title: localized("筛选要提醒的会议", "Filter which meetings get reminders"),
                    detail: localized("这些选项只影响提醒，不会改动系统日历。", "These options affect reminders only.")
                )

                preferenceToggleRow(
                    title: localized("仅提醒含视频链接的会议", "Only Meetings with Video Link"),
                    detail: localized("只提醒带会议链接的事件。", "Only remind for events with a meeting link."),
                    isOn: Binding(
                        get: { page.reminderPreferencesController.reminderPreferences.onlyForMeetingsWithVideoLink },
                        set: { isEnabled in Task { await page.reminderPreferencesController.setOnlyForMeetingsWithVideoLink(isEnabled) } }
                    )
                )

                preferenceDivider

                preferenceToggleRow(
                    title: localized("跳过已拒绝会议", "Skip Declined Meetings"),
                    detail: localized("不提醒你已拒绝的会议。", "Don't remind for meetings you've declined."),
                    isOn: Binding(
                        get: { page.reminderPreferencesController.reminderPreferences.skipDeclinedMeetings },
                        set: { isEnabled in Task { await page.reminderPreferencesController.setSkipDeclinedMeetings(isEnabled) } }
                    )
                )
            }
        }
    }

    // MARK: Presentation state

    private var isReminderPreferenceEditingDisabled: Bool {
        page.reminderPreferencesController.loadingState || page.reminderPreferencesController.isSavingState
    }

    private var isCountdownFollowingSelectedSound: Bool {
        page.reminderPreferencesController.reminderPreferences.countdownOverrideSeconds == nil
    }

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

    private var selectedSoundProfileName: String {
        page.soundProfileLibraryController.selectedSoundProfile?.displayName
            ?? localized("默认提醒音效", "Default reminder sound")
    }

    // MARK: Bindings

    private var reminderCountdownModeBinding: Binding<ReminderCountdownMode> {
        Binding(
            get: { isCountdownFollowingSelectedSound ? .followSound : .manual },
            set: { mode in
                Task {
                    switch mode {
                    case .followSound:
                        await page.reminderPreferencesController.setCountdownOverrideSeconds(nil)
                    case .manual:
                        await page.reminderPreferencesController.setCountdownOverrideSeconds(effectiveCountdownSeconds)
                    }
                }
            }
        )
    }

    private var manualCountdownSecondsBinding: Binding<Int> {
        Binding(
            get: { page.reminderPreferencesController.reminderPreferences.countdownOverrideSeconds ?? effectiveCountdownSeconds },
            set: { seconds in Task { await page.reminderPreferencesController.setCountdownOverrideSeconds(seconds) } }
        )
    }

    // MARK: Presentation strings

    private var localizedReminderStateSummary: String {
        switch page.reminderEngine.state {
        case .idle: return localized("当前没有待触发的提醒", "No reminder is waiting to trigger")
        case .scheduled: return localized("下一次提醒已安排", "The next reminder is scheduled")
        case let .playing(context, _):
            if context.triggeredImmediately { return localized("提醒已立即开始执行", "The reminder started immediately") }
            return localized("提醒正在执行倒计时", "The reminder countdown is running")
        case let .triggeredSilently(_, _, reason):
            switch reason {
            case .userMuted: return localized("提醒已触发，但当前为静音模式", "The reminder was triggered, but mute mode is on")
            case .outputRoutePolicy: return localized("提醒已触发，但当前不会播放声音", "The reminder was triggered, but sound playback is blocked")
            }
        case .disabled: return localized("本地提醒已关闭", "Local reminders are turned off")
        case .failed: return localized("提醒当前不可用", "Reminders are currently unavailable")
        }
    }

    private var localizedReminderStatusCardDetail: String {
        switch page.reminderEngine.state {
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

    private var localizedReminderScheduleSnapshotValue: String {
        switch page.reminderEngine.state {
        case .idle: return localized("暂无待触发", "Nothing Pending")
        case let .scheduled(context):
            let leadTime = localizedLeadTimeDescription(triggerAt: context.triggerAt, meetingStartAt: context.meeting.startAt)
            return localized("会前 \(leadTime)", "\(leadTime) before start")
        case let .playing(context, _):
            return context.triggeredImmediately
                ? localized("已立即开始", "Started Immediately")
                : localized("正在倒计时", "Countdown Running")
        case let .triggeredSilently(_, _, reason):
            switch reason {
            case .userMuted: return localized("静音命中", "Muted Trigger")
            case .outputRoutePolicy: return localized("策略静默", "Policy-muted")
            }
        case .disabled: return localized("提醒关闭", "Reminder Off")
        case .failed: return localized("当前不可用", "Unavailable")
        }
    }

    private var localizedOverviewAudioStatusTitle: String {
        if !page.reminderPreferencesController.reminderPreferences.globalReminderEnabled { return localized("不会播放", "Playback Off") }
        if page.reminderPreferencesController.reminderPreferences.isMuted { return localized("静音模式", "Muted") }
        if page.reminderPreferencesController.reminderPreferences.playSoundOnlyWhenHeadphonesConnected { return localized("仅耳机播放", "Headphones Only") }
        return localized("正常播放", "Audible")
    }

    private var localizedReminderLeadTimeSettingDetail: String {
        if isCountdownFollowingSelectedSound {
            return localized(
                "当前跟随 \(selectedSoundProfileName) 的时长；提醒和倒计时会一起开始。",
                "Currently follows \(selectedSoundProfileName); the reminder and countdown start together."
            )
        }
        return localized("当前使用固定秒数；提醒和倒计时会一起开始。", "A fixed duration is active; the reminder and countdown start together.")
    }

    private var localizedReminderCountdownModeValue: String {
        if isCountdownFollowingSelectedSound { return localized("跟随当前音频", "Follow Current Sound") }
        return localized("手动 \(effectiveCountdownDurationLine)", "Manual \(effectiveCountdownDurationLine)")
    }

    private var localizedReminderCountdownModeDetail: String {
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

    // MARK: Badge & symbol

    private var reminderStatusSymbolName: String {
        switch page.reminderEngine.state {
        case .idle: return "bell.badge"
        case .scheduled: return "bell.fill"
        case .playing: return "timer.circle.fill"
        case let .triggeredSilently(_, _, reason):
            switch reason {
            case .userMuted: return "bell.slash.fill"
            case .outputRoutePolicy: return "speaker.slash.fill"
            }
        case .disabled: return "bell.slash.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var reminderStatusBadgeColor: Color {
        switch page.reminderEngine.state {
        case .disabled: return .secondary
        case .failed: return .red
        case .idle: return .orange
        case .scheduled: return .green
        case .playing, .triggeredSilently: return .blue
        }
    }

    // MARK: Duration helpers

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

    private func localizedLeadTimeDescription(triggerAt: Date, meetingStartAt: Date) -> String {
        localizedDurationLine(for: max(1, meetingStartAt.timeIntervalSince(triggerAt)))
    }

    private func localizedScheduledReminderLine(for context: ScheduledReminderContext) -> String {
        let leadTime = localizedLeadTimeDescription(triggerAt: context.triggerAt, meetingStartAt: context.meeting.startAt)
        if context.triggeredImmediately {
            return localized(
                "距离会议已经太近，因此会立即开始提醒，倒计时持续 \(context.countdownSeconds) 秒。",
                "The meeting is too close, so the reminder starts immediately and the countdown lasts \(context.countdownSeconds) seconds."
            )
        }
        return localized(
            "将在会议开始前 \(leadTime) 触发提醒，倒计时持续 \(context.countdownSeconds) 秒。",
            "The reminder will trigger \(leadTime) before the meeting and the countdown lasts \(context.countdownSeconds) seconds."
        )
    }

    // MARK: Shared component helpers

    private func pageIntro(eyebrow: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionEyebrow(eyebrow)
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.secondary.opacity(0.72))
            .tracking(1.4)
    }

    private func statusSnapshotRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(uiLanguage == .english ? title.uppercased() : title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.7))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func preferenceToggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 18) {
                preferenceToggleText(title: title, detail: detail)
                Spacer(minLength: 16)
                VStack(alignment: .trailing, spacing: 8) {
                    preferenceStateLabel(
                        text: preferenceToggleStateText(isOn: isOn.wrappedValue),
                        color: preferenceToggleStateColor(isOn: isOn.wrappedValue)
                    )
                    preferenceToggleControl(isOn: isOn)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                preferenceToggleText(title: title, detail: detail)
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        preferenceStateLabel(
                            text: preferenceToggleStateText(isOn: isOn.wrappedValue),
                            color: preferenceToggleStateColor(isOn: isOn.wrappedValue)
                        )
                        preferenceToggleControl(isOn: isOn)
                    }
                }
            }
        }
    }

    private func preferenceValueRow<Control: View>(
        title: String,
        detail: String,
        value: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 18) {
                preferenceToggleText(title: title, detail: detail)
                Spacer(minLength: 16)
                VStack(alignment: .trailing, spacing: 10) {
                    Text(value)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                    control()
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                preferenceToggleText(title: title, detail: detail)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack { Spacer(); control() }
            }
        }
    }

    private var preferenceDivider: some View {
        Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1)
    }

    private func preferenceToggleText(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 15, weight: .bold))
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func preferenceStateLabel(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(color.opacity(0.12)))
            .overlay(Capsule(style: .continuous).strokeBorder(color.opacity(0.18), lineWidth: 1))
    }

    private func preferenceToggleControl(isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(isReminderPreferenceEditingDisabled)
    }

    private func preferenceToggleStateText(isOn: Bool) -> String {
        if isReminderPreferenceEditingDisabled { return localized("保存中", "Saving") }
        return isOn ? localized("已开启", "Enabled") : localized("已关闭", "Disabled")
    }

    private func preferenceToggleStateColor(isOn: Bool) -> Color {
        if isReminderPreferenceEditingDisabled { return .secondary }
        return isOn ? .green : .secondary
    }

    private func warningStrip(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.red.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.red.opacity(0.16), lineWidth: 1))
    }
}
