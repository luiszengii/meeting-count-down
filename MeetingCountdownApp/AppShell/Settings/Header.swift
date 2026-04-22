import SwiftUI

/// 这个文件集中放设置窗口头部和 tab 导航。
/// 它们是所有页面共享的壳层入口，因此从主文件里独立出来，
/// 让真正的 tab 内容不再和全局导航交错在一起。
///
/// 2026-04-22 更新：tabContent 改为遍历页面注册表渲染，不再维护 switch 分支。
extension SettingsView {
    /// 不同 tab 共用同一套 hero 骨架，但标题、副标题和 badge 应该随页面任务切换。
    var currentHeaderContent: SettingsHeaderContent {
        switch selectedTab {
        case .overview:
            return SettingsHeaderContent(
                title: localizedOverviewPageTitle,
                subtitle: localizedOverviewPageSubtitle,
                badges: overviewHeaderBadges
            )
        case .calendar:
            return SettingsHeaderContent(
                title: localized("日历", "Calendar"),
                subtitle: localized(
                    "管理日历连接，并选择哪些日历中的会议会触发提醒",
                    "Manage calendar connection and choose which calendars can trigger reminders"
                ),
                badges: calendarHeaderBadges
            )
        case .reminders:
            return SettingsHeaderContent(
                title: localizedReminderPageTitle,
                subtitle: localizedReminderPageSubtitle,
                badges: reminderHeaderBadges
            )
        case .audio:
            return SettingsHeaderContent(
                title: localized("音频", "Audio"),
                subtitle: localized(
                    "管理当前提醒音频、试听效果和导入的声音列表。",
                    "Manage the current reminder sound, previews, and imported sounds."
                ),
                badges: [
                    SettingsHeaderBadgeItem(text: selectedSoundProfileName, color: .blue),
                    SettingsHeaderBadgeItem(
                        text: localized(
                            "已导入 \(soundProfileLibraryController.soundProfiles.count) 条音频",
                            "\(soundProfileLibraryController.soundProfiles.count) sound(s) available"
                        ),
                        color: .secondary
                    )
                ]
            )
        case .advanced:
            return SettingsHeaderContent(
                title: localized("高级", "Advanced"),
                subtitle: localized(
                    "管理语言、开机启动，并在需要时导出诊断信息。",
                    "Manage language, launch-at-login behavior, and export diagnostics when needed."
                ),
                badges: [
                    SettingsHeaderBadgeItem(text: localizedSyncFreshnessBadgeText, color: diagnosticBadgeColor(for: syncFreshnessStatus)),
                    SettingsHeaderBadgeItem(
                        text: launchAtLoginController.isEnabled
                            ? localized("开机启动已开启", "Launch at Login On")
                            : localized("开机启动已关闭", "Launch at Login Off"),
                        color: launchAtLoginController.isEnabled ? .green : .secondary
                    )
                ]
            )
        }
    }

    /// 顶部主卡继续共用同一套骨架，但不再用固定高度强行撑开内容。
    var header: some View {
        GlassPanel(cornerRadius: 30, padding: 20, overlayOpacity: 0.14) {
            settingsHeroCard(
                title: currentHeaderContent.title,
                subtitle: currentHeaderContent.subtitle,
                badges: currentHeaderContent.badges
            )
        }
    }

    /// 主卡内部改成内容驱动高度，避免 hero 为了"稳"而把空白感重新带回来。
    func settingsHeroCard(title: String, subtitle: String, badges: [SettingsHeaderBadgeItem]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.96))

            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 720, alignment: .leading)

            settingsHeroBadgeArea(badges: badges)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// badge 区也固定成两行回退结构，并给底部区域一个最小高度，避免不同 tab 之间高度忽长忽短。
    func settingsHeroBadgeArea(badges: [SettingsHeaderBadgeItem]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ForEach(badges) { badge in
                    GlassBadge(text: badge.text, color: badge.color)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(badges.chunked(into: 2).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 10) {
                        ForEach(row) { badge in
                            GlassBadge(text: badge.text, color: badge.color)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        }
    }

    /// tab 导航遍历页面注册表，而不是 SettingsTab 枚举，
    /// 保证导航顺序与注册表顺序一致，新增页面只需注册一次。
    var tabBar: some View {
        GlassSegmentedTabs(selection: $selectedTab) { tab in
            tab.title(for: uiLanguage)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 找到当前选中页并渲染其 body，找不到时显示空视图（防御性处理）。
    @ViewBuilder
    var tabContent: some View {
        ZStack(alignment: .topLeading) {
            ForEach(SettingsTab.allCases) { tab in
                if selectedTab == tab, let page = pages.first(where: { $0.id == tab }) {
                    page.body(uiLanguage: uiLanguage)
                        .transition(.settingsPageSwap)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(GlassMotion.page, value: selectedTab)
    }
}

struct SettingsHeaderBadgeItem: Identifiable {
    let id = UUID()
    let text: String
    let color: Color
}

/// `SettingsHeaderContent` 把 hero 主卡真正需要的标题、副标题和 badge 聚成一份只读展示态，
/// 避免 `header` 本体里再塞一长串 `switch` 分支和页面特判。
struct SettingsHeaderContent {
    let title: String
    let subtitle: String
    let badges: [SettingsHeaderBadgeItem]
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else {
            return [self]
        }

        var result: [[Element]] = []
        var index = startIndex

        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index ..< nextIndex]))
            index = nextIndex
        }

        return result
    }
}
