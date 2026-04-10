import AppKit
import SwiftUI

/// 这个文件承载概览页。
/// 它优先回答“现在能不能提醒”“下一场会议是什么”“同步是否正常”，
/// 让用户不用先钻进其他 tab 才能判断当前状态。
extension SettingsView {
    /// Overview 由一个主舞台和一个次级状态区组成，最后再补充关键摘要。
    var overviewPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 22) {
                    overviewHeroPanel
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 16) {
                        overviewStatePanel
                        overviewSyncPanel
                    }
                    .frame(width: 320)
                }

                VStack(alignment: .leading, spacing: 18) {
                    overviewHeroPanel
                    overviewStatePanel
                    overviewSyncPanel
                }
            }

            overviewSummaryBand
        }
    }

    var overviewHeroPanel: some View {
        GlassPanel(cornerRadius: 32, padding: 22, overlayOpacity: 0.16) {
            VStack(alignment: .leading, spacing: 20) {
                pageIntro(
                    eyebrow: localized("总览", "OVERVIEW"),
                    title: localized("先看提醒是不是正常", "Check whether reminders are ready"),
                    detail: localized(
                        "这里会显示下一场会议、提醒状态和同步情况。",
                        "See your next meeting, reminder status, and sync health here."
                    )
                )

                if let nextMeeting = sourceCoordinator.state.nextMeeting {
                    VStack(alignment: .leading, spacing: 18) {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 18) {
                                nextMeetingHeadline(for: nextMeeting)
                                Spacer(minLength: 0)
                                overviewHeroActions(for: nextMeeting)
                            }

                            VStack(alignment: .leading, spacing: 16) {
                                nextMeetingHeadline(for: nextMeeting)
                                overviewHeroActions(for: nextMeeting)
                            }
                        }

                        GlassCard(cornerRadius: 24, padding: 16, tintOpacity: 0.16) {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 14) {
                                    overviewHeroFact(
                                        title: localized("来源", "Source"),
                                        value: nextMeeting.source.displayName,
                                        accent: .blue
                                    )

                                    Divider()

                                    overviewHeroFact(
                                        title: localized("会议开始", "Starts"),
                                        value: Self.absoluteFormatter.string(from: nextMeeting.startAt),
                                        accent: .green
                                    )

                                    Divider()

                                    overviewHeroFact(
                                        title: localized("剩余时间", "Countdown"),
                                        value: localizedCountdownLine(until: nextMeeting.startAt),
                                        accent: .orange
                                    )
                                }

                                VStack(alignment: .leading, spacing: 12) {
                                    overviewHeroFact(title: localized("来源", "Source"), value: nextMeeting.source.displayName, accent: .blue)
                                    overviewHeroFact(title: localized("会议开始", "Starts"), value: Self.absoluteFormatter.string(from: nextMeeting.startAt), accent: .green)
                                    overviewHeroFact(title: localized("剩余时间", "Countdown"), value: localizedCountdownLine(until: nextMeeting.startAt), accent: .orange)
                                }
                            }
                        }
                    }
                } else {
                    emptyStatePanel(
                        title: localized("还没有可提醒会议", "No eligible meeting yet"),
                        detail: localized(
                            "去“日历”页检查权限和日历选择，或稍后再刷新一次。",
                            "Check permissions and calendar selection in Calendar, or refresh again in a moment."
                        )
                    )
                }
            }
        }
    }

    func nextMeetingHeadline(for nextMeeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                GlassBadge(text: nextMeeting.source.displayName, color: .blue)

                if nextMeeting.hasVideoConferenceLink {
                    GlassBadge(text: localized("视频会议", "Video Link"), color: .green)
                }
            }

            Text(nextMeeting.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .lineLimit(2)

            Text(localizedMeetingStartLine(for: nextMeeting))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    /// 主动作只保留“加入会议/打开事件”和“立即刷新”，避免 Overview 变成工具箱。
    func overviewHeroActions(for nextMeeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let meetingURL = nextMeeting.links.first?.url {
                Button {
                    NSWorkspace.shared.open(meetingURL)
                } label: {
                    Text(localizedJoinActionTitle(for: nextMeeting))
                }
                .buttonStyle(GlassPillButtonStyle(tone: .primary))
            }

            Button {
                Task {
                    await sourceCoordinator.refresh(trigger: .manualRefresh)
                }
            } label: {
                Text(localized("立即刷新", "Refresh Now"))
            }
            .buttonStyle(GlassPillButtonStyle(tone: .secondary))
            .disabled(sourceCoordinator.state.isRefreshing)
        }
    }

    func overviewHeroFact(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(uiLanguage == .english ? title.uppercased() : title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent.opacity(0.82))

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var overviewStatePanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 16) {
                pageIntro(
                    eyebrow: localized("提醒", "REMINDER"),
                    title: localized("提醒状态", "Reminder Status"),
                    detail: localizedReminderStateDetailLine
                )

                statusSnapshotRow(
                    title: localized("总开关", "Global Switch"),
                    value: reminderPreferencesController.reminderPreferences.globalReminderEnabled
                        ? localized("已开启", "On")
                        : localized("已关闭", "Off")
                )

                statusSnapshotRow(
                    title: localized("静音模式", "Mute Mode"),
                    value: reminderPreferencesController.reminderPreferences.isMuted
                        ? localized("已静音", "Muted")
                        : localized("正常播放", "Audible")
                )
            }
        }
    }

    var overviewSyncPanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 16) {
                pageIntro(
                    eyebrow: localized("同步", "SYNC"),
                    title: localized("同步状态", "Sync Status"),
                    detail: localizedSyncFreshnessSummary
                )

                statusSnapshotRow(
                    title: localized("最近成功读取", "Last Read"),
                    value: localizedLastRefreshLine
                )

                statusSnapshotRow(
                    title: localized("日历选择", "Calendars"),
                    value: localizedCalendarSelectionSummary
                )
            }
        }
    }

    var overviewSummaryBand: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 18) {
                pageIntro(
                    eyebrow: localized("关键状态", "KEY STATUS"),
                    title: localized("这四项最值得先看", "Start with these four checks"),
                    detail: localized("这几项正常时，提醒通常也会正常工作。", "When these look healthy, reminders usually do too.")
                )

                LazyVGrid(columns: responsiveCardColumns(minimum: 220, maximum: 320), spacing: 14) {
                    summaryCard(
                        title: localized("日历权限", "Calendar Access"),
                        value: localizedAuthorizationBadgeText(for: systemCalendarConnectionController.authorizationState),
                        detail: localizedAuthorizationSummary(for: systemCalendarConnectionController.authorizationState),
                        accent: authorizationBadgeColor(for: systemCalendarConnectionController.authorizationState)
                    )
                    summaryCard(
                        title: localized("生效日历", "Active Calendars"),
                        value: localizedCalendarSelectionSummary,
                        detail: selectedCalendarDetailLine,
                        accent: systemCalendarConnectionController.hasSelectedCalendars ? .green : .orange
                    )
                    summaryCard(
                        title: localized("最近同步", "Last Sync"),
                        value: localizedLastRefreshLine,
                        detail: localizedSyncFreshnessSummary,
                        accent: diagnosticBadgeColor(for: syncFreshnessStatus)
                    )
                    summaryCard(
                        title: localized("应用状态", "App State"),
                        value: sourceCoordinator.state.isRefreshing ? localized("正在刷新…", "Refreshing...") : localizedHealthStateSummary,
                        detail: nextMeetingDetailLine,
                        accent: reminderStatusBadgeColor
                    )
                }
            }
        }
    }
}
