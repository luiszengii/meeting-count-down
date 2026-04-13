import AppKit
import SwiftUI

/// 这个文件承载概览页。
/// 新结构不再解释“用户应该怎么看界面”，而是直接把当前系统事实、下一场会议和可执行动作排出来，
/// 让设置窗口首页更像状态面板，而不是设计说明页。
extension SettingsView {
    var overviewPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            overviewMeetingPanel
            overviewSupportPanels
            overviewSummaryGrid
            overviewIssuePanel
        }
    }

    /// 下一场会议仍然是概览页的主舞台。
    /// 它优先回答“哪场会”“什么时候开始”“系统会不会提醒”这三个问题。
    var overviewMeetingPanel: some View {
        GlassPanel(cornerRadius: 32, padding: 22, overlayOpacity: 0.16) {
            VStack(alignment: .leading, spacing: 18) {
                Text(localized("下一场会议", "Next Meeting"))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.95))

                if let nextMeeting = sourceCoordinator.state.nextMeeting {
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
                        Text(localized("当前还没有待提醒的会议", "No Meeting Is Ready to Remind Yet"))
                            .font(.system(size: 20, weight: .bold, design: .rounded))

                        Text(localizedHealthStateSummary)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            activateOverviewTab(.calendar)
                        } label: {
                            Text(localized("去检查日历连接", "Check Calendar Setup"))
                        }
                        .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                    }
                }
            }
        }
    }

    /// 下一场会的元信息压成两条事实，避免再出现“来源/开始/剩余时间”那种偏 dashboard 模板的三段式。
    func overviewMeetingMetadata(for meeting: MeetingRecord) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                overviewMeetingMetaFact(
                    title: localized("来源日历", "Calendar"),
                    value: meeting.source.displayName
                )

                overviewMeetingMetaFact(
                    title: localized("会议类型", "Meeting Type"),
                    value: meeting.hasVideoConferenceLink
                        ? localized("视频会议", "Video Meeting")
                        : localized("普通事件", "Calendar Event")
                )
            }
            .frame(minWidth: 700, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                overviewMeetingMetaFact(
                    title: localized("来源日历", "Calendar"),
                    value: meeting.source.displayName
                )

                overviewMeetingMetaFact(
                    title: localized("会议类型", "Meeting Type"),
                    value: meeting.hasVideoConferenceLink
                        ? localized("视频会议", "Video Meeting")
                        : localized("普通事件", "Calendar Event")
                )
            }
        }
    }

    func overviewMeetingMetaFact(title: String, value: String) -> some View {
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

    /// 主操作收敛成单一主入口和同步按钮，避免两个按钮打开同一条链接。
    func overviewMeetingActions(for meeting: MeetingRecord) -> some View {
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
                        await sourceCoordinator.refresh(trigger: .manualRefresh)
                    }
                } label: {
                    Text(localized("立即同步", "Sync Now"))
                }
                .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                .disabled(sourceCoordinator.state.isRefreshing)
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
                        await sourceCoordinator.refresh(trigger: .manualRefresh)
                    }
                } label: {
                    Text(localized("立即同步", "Sync Now"))
                }
                .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                .disabled(sourceCoordinator.state.isRefreshing)
            }
        }
    }

    /// 第二行保持“提醒状态 / 同步状态”双卡。
    /// 这里继续把横排阈值压低，让约 680 宽的实际设置窗口更容易维持双卡并排。
    var overviewSupportPanels: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                overviewDetailActionCard(
                    title: localized("提醒状态", "Reminder Status"),
                    rows: [
                        (localized("当前提醒", "Reminder"), localizedOverviewReminderStatusTitle),
                        (localized("触发方式", "Trigger"), localizedOverviewTriggerModeTitle),
                        (localized("倒计时", "Countdown"), effectiveCountdownDurationLine),
                        (localized("音频播放", "Audio"), localizedOverviewAudioStatusTitle)
                    ],
                    actionTitle: localized("调整提醒设置", "Adjust Reminder Settings")
                ) {
                    activateOverviewTab(.reminders)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                overviewDetailActionCard(
                    title: localized("同步状态", "Sync Status"),
                    rows: [
                        (localized("最近同步", "Last Sync"), localizedLastRefreshLine),
                        (localized("同步结果", "Result"), localizedOverviewSyncResultTitle),
                        (localized("数据来源", "Source"), localized("CalDAV 单一路径", "CalDAV Only")),
                        (
                            localized("生效日历", "Active Calendars"),
                            localized(
                                "\(systemCalendarConnectionController.selectedCalendarIDs.count) 个日历",
                                "\(systemCalendarConnectionController.selectedCalendarIDs.count) calendar(s)"
                            )
                        )
                    ],
                    actionTitle: localized("查看同步详情", "View Sync Details")
                ) {
                    activateOverviewTab(.advanced)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 560, alignment: .leading)

            VStack(alignment: .leading, spacing: 14) {
                overviewDetailActionCard(
                    title: localized("提醒状态", "Reminder Status"),
                    rows: [
                        (localized("当前提醒", "Reminder"), localizedOverviewReminderStatusTitle),
                        (localized("触发方式", "Trigger"), localizedOverviewTriggerModeTitle),
                        (localized("倒计时", "Countdown"), effectiveCountdownDurationLine),
                        (localized("音频播放", "Audio"), localizedOverviewAudioStatusTitle)
                    ],
                    actionTitle: localized("调整提醒设置", "Adjust Reminder Settings")
                ) {
                    activateOverviewTab(.reminders)
                }

                overviewDetailActionCard(
                    title: localized("同步状态", "Sync Status"),
                    rows: [
                        (localized("最近同步", "Last Sync"), localizedLastRefreshLine),
                        (localized("同步结果", "Result"), localizedOverviewSyncResultTitle),
                        (localized("数据来源", "Source"), localized("CalDAV 单一路径", "CalDAV Only")),
                        (
                            localized("生效日历", "Active Calendars"),
                            localized(
                                "\(systemCalendarConnectionController.selectedCalendarIDs.count) 个日历",
                                "\(systemCalendarConnectionController.selectedCalendarIDs.count) calendar(s)"
                            )
                        )
                    ],
                    actionTitle: localized("查看同步详情", "View Sync Details")
                ) {
                    activateOverviewTab(.advanced)
                }
            }
        }
    }

    /// 四宫格继续保留，但每张卡只讲一个状态，并配一个直接动作。
    var overviewSummaryGrid: some View {
        LazyVGrid(columns: responsiveCardColumns(minimum: 250, maximum: 340), spacing: 14) {
            overviewSummaryActionCard(
                title: localized("日历权限", "Calendar Access"),
                value: localizedOverviewPermissionStatusTitle,
                detail: localizedOverviewPermissionDetail,
                accent: authorizationBadgeColor(for: systemCalendarConnectionController.authorizationState),
                actionTitle: localized("管理权限", "Manage Permission")
            ) {
                openCalendarPrivacySettings()
            }

            overviewSummaryActionCard(
                title: localized("生效日历", "Active Calendars"),
                value: localizedOverviewActiveCalendarsTitle,
                detail: localizedSelectedCalendarNamesDetail,
                accent: systemCalendarConnectionController.hasSelectedCalendars ? .green : .orange,
                actionTitle: localized("选择日历", "Choose Calendars")
            ) {
                activateOverviewTab(.calendar)
            }

            overviewSummaryActionCard(
                title: localized("音频状态", "Audio Status"),
                value: localizedOverviewAudioStatusTitle,
                detail: localizedOverviewAudioStatusDetail,
                accent: reminderPreferencesController.reminderPreferences.isMuted ? .orange : .blue,
                actionTitle: localized("测试提醒音频", "Test Reminder Sound")
            ) {
                guard let selectedSoundProfile = soundProfileLibraryController.selectedSoundProfile else {
                    activateOverviewTab(.audio)
                    return
                }

                Task {
                    await soundProfileLibraryController.togglePreview(for: selectedSoundProfile.id)
                }
            }

            overviewSummaryActionCard(
                title: localized("应用状态", "App Status"),
                value: localizedOverviewAppStatusTitle,
                detail: localizedOverviewAppStatusDetail,
                accent: overviewHealthBadgeColor,
                actionTitle: localized("查看诊断信息", "View Diagnostics")
            ) {
                activateOverviewTab(.advanced)
            }
        }
    }

    /// 问题区默认显示“当前无异常”，一旦真正出现错误，会优先换成故障说明。
    var overviewIssuePanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(localized("最近发现的问题", "Recent Issues"))
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

    /// 这一类卡片承接“提醒状态 / 同步状态”这种多行事实说明。
    func overviewDetailActionCard(
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

    /// 四宫格卡片沿用小卡片密度，但补上直接动作，避免用户看完状态还得自己找入口。
    func overviewSummaryActionCard(
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

    func overviewKeyValueRow(title: String, value: String) -> some View {
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

    /// 这里优先显示“系统会怎么提醒这场会”，而不是再解释这张卡片的用途。
    func overviewReminderLine(for meeting: MeetingRecord) -> String {
        switch reminderEngine.state {
        case let .scheduled(context):
            if isReminderContext(context, for: meeting) {
                return localizedScheduledReminderLine(for: context)
            }
        case let .playing(context, startedAt):
            if isReminderContext(context, for: meeting) {
                return localized(
                    "已在 \(Self.absoluteFormatter.string(from: startedAt)) 开始提醒，倒计时持续 \(context.countdownSeconds) 秒。",
                    "The reminder started at \(Self.absoluteFormatter.string(from: startedAt)) and the countdown lasts \(context.countdownSeconds) seconds."
                )
            }
        case let .triggeredSilently(context, triggeredAt, reason):
            if isReminderContext(context, for: meeting) {
                switch reason {
                case .userMuted:
                    return localized(
                        "已在 \(Self.absoluteFormatter.string(from: triggeredAt)) 触发提醒，但当前是静音模式。",
                        "The reminder was triggered at \(Self.absoluteFormatter.string(from: triggeredAt)), but mute mode is on."
                    )
                case .outputRoutePolicy:
                    return localized(
                        "已在 \(Self.absoluteFormatter.string(from: triggeredAt)) 触发提醒，但当前输出设备不会播放声音。",
                        "The reminder was triggered at \(Self.absoluteFormatter.string(from: triggeredAt)), but the current audio output won't play sound."
                    )
                }
            }
        case .disabled:
            return localized("当前已关闭本地提醒，这场会议不会触发提醒。", "Local reminders are turned off, so this meeting won't trigger a reminder.")
        case .failed(let message):
            return message
        case .idle:
            break
        }

        return localized(
            "默认会在会议开始前 \(effectiveCountdownDurationLine) 触发提醒，倒计时持续 \(effectiveCountdownSeconds) 秒。",
            "By default, the reminder triggers \(effectiveCountdownDurationLine) before the meeting and the countdown lasts \(effectiveCountdownSeconds) seconds."
        )
    }

    func preferredJoinLink(for meeting: MeetingRecord) -> MeetingLink? {
        if let videoLink = meeting.links.first(where: { $0.kind == .vc }) {
            return videoLink
        }

        return meeting.links.first
    }

    /// Overview 里的动作主要是页内路由，因此统一走同一条 tab 切换入口。
    func activateOverviewTab(_ tab: SettingsTab) {
        withAnimation(GlassMotion.page) {
            selectedTab = tab
        }
    }

}
