import SwiftUI

/// 这个文件负责音频设置页。
/// 这里同时处理“当前音频是什么”“倒计时跟随什么时长”以及“声音列表”，
/// 但通过拆到单独文件，避免音频相关逻辑继续淹没其他 tab。
extension SettingsView {
    var audioPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            audioHeroPanel
            soundLibraryPanel
        }
    }

    var audioHeroPanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.14) {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 14) {
                            pageIntro(
                                eyebrow: localized("音频", "AUDIO"),
                                title: localized("当前提醒音频", "Current Reminder Sound"),
                                detail: localized(
                                    "试听、切换，或上传新的提醒音频；提醒时长设置已收口到“提醒”页。",
                                    "Preview, switch, or upload reminder sounds. Timing settings now live in Reminders."
                                )
                            )

                            summaryCard(
                                title: localized("当前音频", "Current Sound"),
                                value: currentSoundProfileLine,
                                detail: countdownFollowLine,
                                accent: .blue
                            )
                        }

                        Spacer(minLength: 0)

                        Button {
                            isPresentingSoundImporter = true
                        } label: {
                            Text(localized("上传音频", "Upload Audio"))
                        }
                        .buttonStyle(GlassPillButtonStyle(tone: .primary))
                        .disabled(isSoundProfileEditingDisabled)
                    }
                    .frame(minWidth: 780, alignment: .leading)

                    VStack(alignment: .leading, spacing: 14) {
                        pageIntro(
                            eyebrow: localized("音频", "AUDIO"),
                            title: localized("当前提醒音频", "Current Reminder Sound"),
                            detail: localized(
                                "试听、切换，或上传新的提醒音频；提醒时长设置已收口到“提醒”页。",
                                "Preview, switch, or upload reminder sounds. Timing settings now live in Reminders."
                            )
                        )

                        summaryCard(
                            title: localized("当前音频", "Current Sound"),
                            value: currentSoundProfileLine,
                            detail: countdownFollowLine,
                            accent: .blue
                        )

                        Button {
                            isPresentingSoundImporter = true
                        } label: {
                            Text(localized("上传音频", "Upload Audio"))
                        }
                        .buttonStyle(GlassPillButtonStyle(tone: .primary))
                        .disabled(isSoundProfileEditingDisabled)
                    }
                }

                if let errorMessage = soundProfileLibraryController.errorMessage {
                    warningStrip(errorMessage)
                }
            }
        }
    }

    var soundLibraryPanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 18) {
                pageIntro(
                    eyebrow: localized("声音列表", "SOUNDS"),
                    title: localized("选择要播放的声音", "Choose the sound to play"),
                    detail: localized("你可以试听、设为当前，或删除已导入的音频。", "Preview, select, or delete imported sounds.")
                )

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(soundProfileLibraryController.soundProfiles) { soundProfile in
                        soundProfileRow(for: soundProfile)
                    }
                }
            }
        }
    }
}
