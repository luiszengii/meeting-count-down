import SwiftUI

/// 这个文件收口设置页共享组件。
/// 这些小块如果继续散落在各个 tab 文件里，很快就会重新长回一份“复制粘贴版设置页”。
extension SettingsView {
    /// 概览里的摘要卡需要在多个页面复用，因此抽成统一组件。
    func summaryCard(title: String, value: String, detail: String, accent: Color) -> some View {
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

    /// 行式开关用来承接提醒和高级设置，避免每个开关都变成一张卡。
    /// 右侧额外补一枚显式状态胶囊，降低用户只靠绿色 / 灰色识别开关状态的成本。
    func preferenceToggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
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

    /// 提醒页的时间参数更接近“当前值 + 调节控件”，因此补一套共享行骨架。
    func preferenceValueRow<Control: View>(
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

                HStack {
                    Spacer()
                    control()
                }
            }
        }
    }

    var preferenceDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(height: 1)
    }

    func pageIntro(eyebrow: String, title: String, detail: String) -> some View {
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

    func statusSnapshotRow(title: String, value: String) -> some View {
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

    func warningStrip(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.red.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.16), lineWidth: 1)
            )
    }

    func emptyStatePanel(title: String, detail: String) -> some View {
        GlassCard(cornerRadius: 24, padding: 16, tintOpacity: 0.14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))

                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func infoRow(title: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 128, alignment: .leading)

                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 开关行的文字区单独抽出来，避免横排和竖排两套布局重复一份文案结构。
    func preferenceToggleText(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .bold))

            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 设置行状态统一走轻量胶囊，避免每个 tab 再各自发明“已开启 / 已关闭”的样式。
    func preferenceStateLabel(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(color.opacity(0.18), lineWidth: 1)
            )
    }

    /// 开关本身保持统一样式，布局变化时只移动位置，不改交互和禁用规则。
    func preferenceToggleControl(isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(isReminderPreferenceEditingDisabled)
    }

    func preferenceToggleStateText(isOn: Bool) -> String {
        if isReminderPreferenceEditingDisabled {
            return localized("保存中", "Saving")
        }

        return isOn ? localized("已开启", "Enabled") : localized("已关闭", "Disabled")
    }

    func preferenceToggleStateColor(isOn: Bool) -> Color {
        if isReminderPreferenceEditingDisabled {
            return .secondary
        }

        return isOn ? .green : .secondary
    }

    func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.secondary.opacity(0.72))
            .tracking(1.4)
    }

    func setupStepRow(title: String, detail: String, isComplete: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isComplete ? Color.green : Color.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 日历页的异常提示统一走这一套样式。
    /// 正常态弱化，异常态通过整块背景和动作按钮来抬高优先级。
    func statusCallout(
        title: String,
        detail: String,
        tone: StatusCalloutTone,
        actions: [StatusCalloutAction] = []
    ) -> some View {
        let palette = tone.palette

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.title)

                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.detail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !actions.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        ForEach(actions) { action in
                            Button(action: action.handler) {
                                Text(action.title)
                            }
                            .buttonStyle(GlassPillButtonStyle(tone: action.tone))
                        }
                    }
                    .frame(minWidth: 480, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(actions) { action in
                            Button(action: action.handler) {
                                Text(action.title)
                            }
                            .buttonStyle(GlassPillButtonStyle(tone: action.tone))
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(palette.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        )
    }

    /// 日历候选改成紧凑列表行，不再让每个日历都独立占据一整张卡片。
    func calendarRow(for calendar: SystemCalendarDescriptor) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(
                isOn: Binding(
                    get: {
                        systemCalendarConnectionController.selectedCalendarIDs.contains(calendar.id)
                    },
                    set: { isSelected in
                        Task {
                            await systemCalendarConnectionController.setCalendarSelection(
                                calendarID: calendar.id,
                                isSelected: isSelected
                            )
                        }
                    }
                )
            ) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(localizedCalendarDisplayName(for: calendar))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    if let tag = localizedCalendarAccessoryTag(for: calendar) {
                        calendarAccessoryTag(tag)
                    }
                }

                Text(localizedCalendarSubtitle(for: calendar))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    func calendarAccessoryTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.primary.opacity(0.74))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
    }

    /// 音频条目需要 hover 态和动作菜单，因此集中放在共享组件里维护。
    func soundProfileRow(for soundProfile: SoundProfile) -> some View {
        let isCurrent = soundProfile.id == soundProfileLibraryController.selectedSoundProfileID
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
            hoveredSoundProfileID = isHovering ? soundProfile.id : (hoveredSoundProfileID == soundProfile.id ? nil : hoveredSoundProfileID)
        }
        .animation(GlassMotion.hover, value: isHovered)
    }

    func soundProfileRowHeader(for soundProfile: SoundProfile, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(soundProfile.displayName)
                        .font(.system(size: 15, weight: .bold))

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

    func soundProfileRowActions(for soundProfile: SoundProfile, isCurrent: Bool, shouldShowMoreMenu: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await soundProfileLibraryController.togglePreview(for: soundProfile.id)
                }
            } label: {
                Text(soundProfileLibraryController.currentlyPreviewingSoundProfileID == soundProfile.id
                    ? localized("停止试听", "Stop Preview")
                    : localized("试听", "Preview"))
            }
            .buttonStyle(GlassPillButtonStyle(tone: .secondary))
            .disabled(soundProfileLibraryController.loadingState)

            if isCurrent {
                Button {
                    Task {
                        await soundProfileLibraryController.selectSoundProfile(id: soundProfile.id)
                    }
                } label: {
                    Text(localized("保持当前", "Keep Current"))
                }
                .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                .disabled(isSoundProfileEditingDisabled)
            } else if shouldShowMoreMenu {
                Menu {
                    Button {
                        Task {
                            await soundProfileLibraryController.selectSoundProfile(id: soundProfile.id)
                        }
                    } label: {
                        Label(localized("设为当前音频", "Set as Current"), systemImage: "checkmark.circle")
                    }

                    if soundProfile.isImported {
                        Button(role: .destructive) {
                            Task {
                                await soundProfileLibraryController.deleteSoundProfile(id: soundProfile.id)
                            }
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

/// 状态提示块会根据语义切换不同的低饱和背景与边框颜色。
enum StatusCalloutTone {
    case warning
    case error

    var palette: (background: Color, border: Color, title: Color, detail: Color) {
        switch self {
        case .warning:
            return (
                Color.orange.opacity(0.08),
                Color.orange.opacity(0.18),
                Color.primary.opacity(0.92),
                Color.primary.opacity(0.72)
            )
        case .error:
            return (
                Color.red.opacity(0.08),
                Color.red.opacity(0.18),
                Color.primary.opacity(0.92),
                Color.primary.opacity(0.72)
            )
        }
    }
}

/// 为了让异常态按钮能在 `ForEach` 里稳定渲染，动作本身也抽成轻量模型。
struct StatusCalloutAction: Identifiable {
    let id = UUID()
    let title: String
    let tone: GlassPillButtonStyle.Tone
    let handler: () -> Void
}

    var soundProfileMoreLabel: some View {
        let background = Capsule(style: .continuous)
            .fill(Color.white.opacity(0.18))
        let outline = Capsule(style: .continuous)
            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)

        return Text(localized("更多", "More"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background)
            .overlay(outline)
    }
}
