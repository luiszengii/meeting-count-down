import SwiftUI

/// 这个文件集中放设置窗口头部和 tab 导航。
/// 它们是所有页面共享的壳层入口，因此从主文件里独立出来，
/// 让真正的 tab 内容不再和全局导航交错在一起。
extension SettingsView {
    /// 顶部区改成真正的系统状态摘要卡。
    /// 它不再解释“这个页面是做什么的”，而是直接告诉用户当前运行状态。
    var header: some View {
        GlassPanel(cornerRadius: 30, padding: 20, overlayOpacity: 0.14) {
            headerTitleBlock
        }
    }

    var headerTitleBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localizedOverviewPageTitle)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.96))

            Text(localizedOverviewPageSubtitle)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: 700, alignment: .leading)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    headerStatusBadges
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        GlassBadge(text: localizedOverviewHealthBadgeText, color: overviewHealthBadgeColor)
                        GlassBadge(text: localizedOverviewConnectionBadgeText, color: hasAddedCalDAVAccount ? .blue : .orange)
                    }

                    HStack(spacing: 10) {
                        GlassBadge(
                            text: localizedOverviewAuthorizationBadgeText,
                            color: authorizationBadgeColor(for: systemCalendarConnectionController.authorizationState)
                        )
                        GlassBadge(
                            text: localizedOverviewSyncBadgeText,
                            color: diagnosticBadgeColor(for: syncFreshnessStatus)
                        )
                    }
                }
            }
        }
    }

    var headerStatusBadges: some View {
        Group {
            GlassBadge(text: localizedOverviewHealthBadgeText, color: overviewHealthBadgeColor)
            GlassBadge(text: localizedOverviewConnectionBadgeText, color: hasAddedCalDAVAccount ? .blue : .orange)
            GlassBadge(
                text: localizedOverviewAuthorizationBadgeText,
                color: authorizationBadgeColor(for: systemCalendarConnectionController.authorizationState)
            )
            GlassBadge(
                text: localizedOverviewSyncBadgeText,
                color: diagnosticBadgeColor(for: syncFreshnessStatus)
            )
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
