import SwiftUI

/// 音频设置页已从 SettingsView extension 迁移为独立 struct，实现 SettingsPage 协议。
/// hover 状态现由 AudioPage 自身持有，fileImporter 触发通过 Binding<Bool> 传入。
///
/// 详见 ADR: docs/adrs/2026-04-22-settings-page-registry.md
struct AudioPage: SettingsPage {
    @ObservedObject var soundProfileLibraryController: SoundProfileLibraryController
    @ObservedObject var reminderPreferencesController: ReminderPreferencesController

    /// fileImporter 的触发绑定：因为 .fileImporter 修饰符挂在 SettingsView 上，
    /// 所以这个 Binding 向上传递，让 AudioPage 能发起导入请求。
    @Binding var isPresentingSoundImporter: Bool

    var id: SettingsTab { .audio }
    var titleKey: (chinese: String, english: String) { ("音频", "Audio") }

    @MainActor func body(uiLanguage: AppUILanguage) -> AnyView {
        AnyView(AudioPageBody(page: self, uiLanguage: uiLanguage))
    }
}

// MARK: - Body view

private struct AudioPageBody: View {
    let page: AudioPage
    let uiLanguage: AppUILanguage

    /// 鼠标悬停的音频条目 ID，用于控制"更多"菜单的显示。
    @State private var hoveredSoundProfileID: SoundProfile.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            audioHeroPanel
            soundLibraryPanel
        }
    }

    // MARK: Localization shorthand

    private func localized(_ chinese: String, _ english: String) -> String {
        FeishuMeetingCountdown.localized(chinese, english, in: uiLanguage)
    }

    // MARK: Hero panel

    private var audioHeroPanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.14) {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 14) {
                            pageIntro(
                                eyebrow: localized("音频", "AUDIO"),
                                title: localized("当前提醒音频", "Current Reminder Sound"),
                                detail: localized(
                                    "试听、切换，或上传新的提醒音频；提醒时长设置已收口到\u{201C}提醒\u{201D}页。",
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

                        Button { page.isPresentingSoundImporter = true } label: {
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
                                "试听、切换，或上传新的提醒音频；提醒时长设置已收口到\u{201C}提醒\u{201D}页。",
                                "Preview, switch, or upload reminder sounds. Timing settings now live in Reminders."
                            )
                        )

                        summaryCard(
                            title: localized("当前音频", "Current Sound"),
                            value: currentSoundProfileLine,
                            detail: countdownFollowLine,
                            accent: .blue
                        )

                        Button { page.isPresentingSoundImporter = true } label: {
                            Text(localized("上传音频", "Upload Audio"))
                        }
                        .buttonStyle(GlassPillButtonStyle(tone: .primary))
                        .disabled(isSoundProfileEditingDisabled)
                    }
                }

                if let errorMessage = page.soundProfileLibraryController.errorMessage {
                    warningStrip(errorMessage)
                }
            }
        }
    }

    // MARK: Sound library panel

    private var soundLibraryPanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 18) {
                pageIntro(
                    eyebrow: localized("声音列表", "SOUNDS"),
                    title: localized("选择要播放的声音", "Choose the sound to play"),
                    detail: localized("你可以试听、设为当前，或删除已导入的音频。", "Preview, select, or delete imported sounds.")
                )

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(page.soundProfileLibraryController.soundProfiles) { soundProfile in
                        soundProfileRow(for: soundProfile)
                    }
                }
            }
        }
    }

    // MARK: Sound profile row

    private func soundProfileRow(for soundProfile: SoundProfile) -> some View {
        let isCurrent = soundProfile.id == page.soundProfileLibraryController.selectedSoundProfileID
        let isHovered = hoveredSoundProfileID == soundProfile.id
        let shouldShowMoreMenu = !isCurrent && isHovered
        let fillOpacity = isCurrent ? 0.2 : (isHovered ? 0.14 : 0.08)
        let strokeOpacity = isCurrent ? 0.34 : 0.18
        let rowShape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        return VStack(alignment: .leading, spacing: 14) {
            soundProfileRowHeader(for: soundProfile, isCurrent: isCurrent)
            soundProfileRowActions(for: soundProfile, isCurrent: isCurrent, shouldShowMoreMenu: shouldShowMoreMenu)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowShape.fill(Color.white.opacity(fillOpacity)))
        .overlay(rowShape.strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 1))
        .scaleEffect(isHovered ? 1.005 : 1)
        .onHover { isHovering in
            hoveredSoundProfileID = isHovering
                ? soundProfile.id
                : (hoveredSoundProfileID == soundProfile.id ? nil : hoveredSoundProfileID)
        }
        .animation(GlassMotion.hover, value: isHovered)
    }

    private func soundProfileRowHeader(for soundProfile: SoundProfile, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(soundProfile.displayName).font(.system(size: 15, weight: .bold))

                    if soundProfile.isBundledDefault {
                        GlassBadge(text: localized("内建", "Built-in"), color: .secondary)
                    }
                    if isCurrent {
                        GlassBadge(text: localized("当前使用中", "Current"), color: .blue)
                    }
                }

                Text(localizedDurationLine(for: soundProfile.duration))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func soundProfileRowActions(for soundProfile: SoundProfile, isCurrent: Bool, shouldShowMoreMenu: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await page.soundProfileLibraryController.togglePreview(for: soundProfile.id) }
            } label: {
                Text(page.soundProfileLibraryController.currentlyPreviewingSoundProfileID == soundProfile.id
                    ? localized("停止试听", "Stop Preview")
                    : localized("试听", "Preview"))
            }
            .buttonStyle(GlassPillButtonStyle(tone: .secondary))
            .disabled(page.soundProfileLibraryController.loadingState)

            if isCurrent {
                Button {
                    Task { await page.soundProfileLibraryController.selectSoundProfile(id: soundProfile.id) }
                } label: {
                    Text(localized("保持当前", "Keep Current"))
                }
                .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                .disabled(isSoundProfileEditingDisabled)
            } else if shouldShowMoreMenu {
                Menu {
                    Button {
                        Task { await page.soundProfileLibraryController.selectSoundProfile(id: soundProfile.id) }
                    } label: {
                        Label(localized("设为当前音频", "Set as Current"), systemImage: "checkmark.circle")
                    }

                    if soundProfile.isImported {
                        Button(role: .destructive) {
                            Task { await page.soundProfileLibraryController.deleteSoundProfile(id: soundProfile.id) }
                        } label: {
                            Label(localized("删除音频", "Delete Audio"), systemImage: "trash")
                        }
                    }
                } label: {
                    soundProfileMoreLabel
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .fixedSize()
                .disabled(isSoundProfileEditingDisabled)
                .glassQuietFocus()
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
    }

    private var soundProfileMoreLabel: some View {
        let background = Capsule(style: .continuous).fill(Color.white.opacity(0.18))
        let outline = Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 1)

        return Text(localized("更多", "More"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background)
            .overlay(outline)
    }

    // MARK: Presentation state

    private var isSoundProfileEditingDisabled: Bool {
        page.soundProfileLibraryController.loadingState
            || page.soundProfileLibraryController.isImportingState
            || page.soundProfileLibraryController.isApplyingState
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

    private var currentSoundProfileLine: String {
        if let profile = page.soundProfileLibraryController.selectedSoundProfile {
            return "\(profile.displayName) · \(localizedDurationLine(for: profile.duration))"
        }
        return localized("默认提醒音效", "Default reminder sound")
    }

    private var countdownFollowLine: String {
        if !isCountdownFollowingSelectedSound {
            return localized(
                "当前倒计时固定为 \(effectiveCountdownDurationLine)，可在\u{201C}提醒\u{201D}页调整。",
                "Countdown is fixed at \(effectiveCountdownDurationLine). Adjust it in Reminders."
            )
        }
        if let profile = page.soundProfileLibraryController.selectedSoundProfile {
            let durationLine = localizedDurationLine(for: profile.duration)
            return localized("当前跟随 \(profile.displayName)（\(durationLine)）。", "Currently follows \(profile.displayName) (\(durationLine)).")
        }
        return localized("当前跟随默认提醒音效时长。", "Currently follows the default reminder sound length.")
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

    private func summaryCard(title: String, value: String, detail: String, accent: Color) -> some View {
        GlassCard(cornerRadius: 24, padding: 16, tintOpacity: 0.18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(uiLanguage == .english ? title.uppercased() : title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent.opacity(0.82))
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        }
        .animation(GlassMotion.page, value: "\(title)|\(value)|\(detail)")
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
