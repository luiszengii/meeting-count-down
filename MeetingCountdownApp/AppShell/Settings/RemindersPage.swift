import SwiftUI

/// 这个文件负责提醒设置页。
/// 它把“提醒是否开启”和“哪些会议应该提醒”拆成两个明确区域，
/// 降低用户在一个大面板里反复来回扫描的成本。
extension SettingsView {
    var remindersPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            remindersHeroPanel
            reminderPolicyPanel
            reminderEligibilityPanel
        }
    }

    var remindersHeroPanel: some View {
        GlassPanel(cornerRadius: 30, padding: 20, overlayOpacity: 0.14) {
            VStack(alignment: .leading, spacing: 18) {
                pageIntro(
                    eyebrow: localized("提醒", "REMINDERS"),
                    title: localized("控制提醒什么时候响", "Choose when reminders should play"),
                    detail: localizedReminderStateDetailLine
                )

                summaryCard(
                    title: localized("当前状态", "Current State"),
                    value: localizedReminderStateSummary,
                    detail: reminderPreferencesController.reminderPreferences.globalReminderEnabled
                        ? localized("提醒已开启。", "Reminders are on.")
                        : localized("提醒已关闭。", "Reminders are off."),
                    accent: reminderStatusBadgeColor
                )

                if reminderPreferencesController.isLoadingState || reminderPreferencesController.isSavingState {
                    ProgressView()
                        .controlSize(.small)
                }

                if let lastErrorMessage = reminderPreferencesController.lastErrorMessage {
                    warningStrip(lastErrorMessage)
                }
            }
        }
    }

    var reminderPolicyPanel: some View {
        GlassPanel(cornerRadius: 30, padding: 20, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 16) {
                pageIntro(
                    eyebrow: localized("播放方式", "PLAYBACK"),
                    title: localized("声音提醒", "Sound Playback"),
                    detail: localized("控制提醒是否播放声音。", "Choose whether reminders play sound.")
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
        GlassPanel(cornerRadius: 30, padding: 20, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 16) {
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
