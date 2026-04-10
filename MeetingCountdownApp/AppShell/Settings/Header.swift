import SwiftUI

/// 这个文件集中放设置窗口头部和 tab 导航。
/// 它们是所有页面共享的壳层入口，因此从主文件里独立出来，
/// 让真正的 tab 内容不再和全局导航交错在一起。
extension SettingsView {
    /// 顶部区先展示“这是什么设置页”，再用右侧快照浓缩当前状态。
    var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 22) {
                headerTitleBlock
                headerSnapshotBoard
                    .frame(width: 340, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 18) {
                headerTitleBlock
                headerSnapshotBoard
            }
        }
    }

    var headerTitleBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("会议倒计时设置", "Meeting Countdown Settings"))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.96))

            Text(localized(
                "管理日历接入、提醒、音频和同步状态。",
                "Manage calendars, reminders, audio, and sync status."
            ))
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: 660, alignment: .leading)

            HStack(spacing: 10) {
                GlassBadge(text: localized("CalDAV 单一路径", "CalDAV Only"), color: .blue)
                GlassBadge(
                    text: localizedAuthorizationBadgeText(for: systemCalendarConnectionController.authorizationState),
                    color: authorizationBadgeColor(for: systemCalendarConnectionController.authorizationState)
                )
                GlassBadge(text: localizedSyncFreshnessBadgeText, color: diagnosticBadgeColor(for: syncFreshnessStatus))
            }
        }
    }

    var headerSnapshotBoard: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.14) {
            VStack(alignment: .leading, spacing: 16) {
                sectionEyebrow(localized("当前状态", "STATUS"))

                statusSnapshotRow(
                    title: localized("下一场会议", "Next Meeting"),
                    value: sourceCoordinator.state.nextMeeting?.title ?? localized("还没有可提醒会议", "No eligible meeting yet")
                )

                statusSnapshotRow(
                    title: localized("提醒状态", "Reminder"),
                    value: localizedReminderStateSummary
                )

                statusSnapshotRow(
                    title: localized("音频", "Audio"),
                    value: currentSoundProfileLine
                )
            }
        }
    }

    /// tab 导航仍然由壳层统一持有，避免子页面自己处理切换状态。
    var tabBar: some View {
        GlassSegmentedTabs(selection: $selectedTab) { tab in
            tab.title(for: uiLanguage)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var tabContent: some View {
        ZStack(alignment: .topLeading) {
            if selectedTab == .overview {
                overviewPage
                    .transition(.settingsPageSwap)
            }

            if selectedTab == .calendar {
                calendarPage
                    .transition(.settingsPageSwap)
            }

            if selectedTab == .reminders {
                remindersPage
                    .transition(.settingsPageSwap)
            }

            if selectedTab == .audio {
                audioPage
                    .transition(.settingsPageSwap)
            }

            if selectedTab == .advanced {
                advancedPage
                    .transition(.settingsPageSwap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(GlassMotion.page, value: selectedTab)
    }
}
