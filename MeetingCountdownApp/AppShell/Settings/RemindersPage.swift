import SwiftUI

/// 这个文件负责提醒设置页。
/// 它把“提醒是否开启”和“哪些会议应该提醒”拆成两个明确区域，
/// 降低用户在一个大面板里反复来回扫描的成本。
extension SettingsView {
    var remindersPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            remindersHeroPanel
            reminderTimingPanel
            reminderPolicyPanel
            reminderEligibilityPanel
        }
    }

    var remindersHeroPanel: some View {
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

                if reminderPreferencesController.isLoadingState || reminderPreferencesController.isSavingState {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)

                        Text(localized("正在保存提醒设置…", "Saving reminder settings..."))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastErrorMessage = reminderPreferencesController.lastErrorMessage {
                    warningStrip(lastErrorMessage)
                }
            }
        }
    }

    var reminderStatusSummaryCard: some View {
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

    var reminderStatusSummaryLeadingIcon: some View {
        ZStack {
            Circle()
                .fill(reminderStatusBadgeColor.opacity(0.14))
                .frame(width: 44, height: 44)

            Image(systemName: reminderStatusSymbolName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(reminderStatusBadgeColor)
        }
    }

    var reminderStatusSummaryCopy: some View {
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

    var reminderStatusSummaryFacts: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                statusSnapshotRow(
                    title: localized("下一次提醒", "Next Reminder"),
                    value: localizedReminderScheduleSnapshotValue
                )

                statusSnapshotRow(
                    title: localized("声音策略", "Sound Policy"),
                    value: localizedOverviewAudioStatusTitle
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                statusSnapshotRow(
                    title: localized("下一次提醒", "Next Reminder"),
                    value: localizedReminderScheduleSnapshotValue
                )

                statusSnapshotRow(
                    title: localized("声音策略", "Sound Policy"),
                    value: localizedOverviewAudioStatusTitle
                )
            }
        }
    }

    var reminderTimingPanel: some View {
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
                            Text(mode.title(for: uiLanguage))
                                .tag(mode)
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

    var reminderPolicyPanel: some View {
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
                        get: { reminderPreferencesController.reminderPreferences.globalReminderEnabled },
                        set: { isEnabled in
                            Task {
                                await reminderPreferencesController.setGlobalReminderEnabled(isEnabled)
                            }
                        }
                    )
                )

                preferenceDivider

                preferenceToggleRow(
                    title: localized("静音模式", "Mute Mode"),
                    detail: localized("保留提醒，但不播放声音。", "Keep reminders on, but mute the sound."),
                    isOn: Binding(
                        get: { reminderPreferencesController.reminderPreferences.isMuted },
                        set: { isMuted in
                            Task {
                                await reminderPreferencesController.setMuted(isMuted)
                            }
                        }
                    )
                )

                preferenceDivider

                preferenceToggleRow(
                    title: localized("仅在耳机连接时播放", "Play Only on Headphones"),
                    detail: localized("外放时会自动静音。", "Sound stays silent when you're on speakers."),
                    isOn: Binding(
                        get: { reminderPreferencesController.reminderPreferences.playSoundOnlyWhenHeadphonesConnected },
                        set: { isEnabled in
                            Task {
                                await reminderPreferencesController.setPlaySoundOnlyWhenHeadphonesConnected(isEnabled)
                            }
                        }
                    )
                )
            }
        }
    }

    var reminderEligibilityPanel: some View {
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
                        get: { reminderPreferencesController.reminderPreferences.onlyForMeetingsWithVideoLink },
                        set: { isEnabled in
                            Task {
                                await reminderPreferencesController.setOnlyForMeetingsWithVideoLink(isEnabled)
                            }
                        }
                    )
                )

                preferenceDivider

                preferenceToggleRow(
                    title: localized("跳过已拒绝会议", "Skip Declined Meetings"),
                    detail: localized("不提醒你已拒绝的会议。", "Don't remind for meetings you've declined."),
                    isOn: Binding(
                        get: { reminderPreferencesController.reminderPreferences.skipDeclinedMeetings },
                        set: { isEnabled in
                            Task {
                                await reminderPreferencesController.setSkipDeclinedMeetings(isEnabled)
                            }
                        }
                    )
                )
            }
        }
    }
}
