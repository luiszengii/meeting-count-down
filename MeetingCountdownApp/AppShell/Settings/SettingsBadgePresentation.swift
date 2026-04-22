import AppKit
import SwiftUI

// MARK: - Badge colors and badge text

/// 徽章颜色、徽章文案和相关行动入口。
/// 这里聚合所有"把某个枚举状态映射到 Color 或 badge 文案"的推导，
/// 不改变业务规则，只做颜色和文案的展示层翻译。
///
/// 2026-04-22 拆分自 Presentation.swift（见 ADR: docs/adrs/2026-04-22-presentation-split.md）
extension SettingsView {

    // MARK: Authorization & diagnostic color mapping

    func authorizationBadgeColor(for state: SystemCalendarAuthorizationState) -> Color {
        switch state {
        case .authorized:
            return .green
        case .notDetermined:
            return .orange
        case .denied, .restricted, .writeOnly:
            return .red
        case .unknown:
            return .secondary
        }
    }

    func diagnosticBadgeColor(for status: DiagnosticCheckStatus) -> Color {
        switch status {
        case .passed:
            return .green
        case .warning:
            return .orange
        case .failed:
            return .red
        case .idle, .pending:
            return .secondary
        }
    }

    func openCalendarPrivacySettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }

    // MARK: Overview header badges

    var localizedOverviewHealthBadgeText: String {
        if sourceCoordinator.state.isRefreshing {
            return localized("正在同步", "Syncing")
        }

        switch sourceCoordinator.state.healthState {
        case .ready:
            return localized("运行正常", "Running Normally")
        case .warning:
            return localized("需要留意", "Needs Attention")
        case .failed:
            return localized("读取失败", "Read Failed")
        case .unconfigured:
            return localized("等待完成设置", "Setup Needed")
        }
    }

    var overviewHealthBadgeColor: Color {
        if sourceCoordinator.state.isRefreshing {
            return .blue
        }

        switch sourceCoordinator.state.healthState {
        case .ready:
            return .green
        case .warning, .unconfigured:
            return .orange
        case .failed:
            return .red
        }
    }

    var localizedOverviewConnectionBadgeText: String {
        hasAddedCalDAVAccount
            ? localized("CalDAV 已连接", "CalDAV Connected")
            : localized("等待连接 CalDAV", "Connect CalDAV")
    }

    var localizedOverviewAuthorizationBadgeText: String {
        switch systemCalendarConnectionController.authorizationState {
        case .authorized:
            return localized("已授权访问日历", "Calendar Access Granted")
        case .notDetermined:
            return localized("等待授权访问日历", "Calendar Access Needed")
        case .denied:
            return localized("日历访问被拒绝", "Calendar Access Denied")
        case .restricted:
            return localized("日历访问受限", "Calendar Access Restricted")
        case .writeOnly:
            return localized("当前只有写入权限", "Write-only Calendar Access")
        case .unknown:
            return localized("日历权限状态未知", "Calendar Access Unknown")
        }
    }

    var localizedOverviewSyncBadgeText: String {
        if sourceCoordinator.state.isRefreshing {
            return localized("正在同步本地日历", "Syncing Local Calendar")
        }

        guard let lastRefreshAt = sourceCoordinator.state.lastRefreshAt else {
            return localized("尚未同步成功", "No Successful Sync Yet")
        }

        let elapsedDescription = localizedElapsedDescription(Date().timeIntervalSince(lastRefreshAt))
        return localized("\(elapsedDescription)前同步成功", "Synced \(elapsedDescription) ago")
    }

    var overviewHeaderBadges: [SettingsHeaderBadgeItem] {
        [
            SettingsHeaderBadgeItem(text: localizedOverviewHealthBadgeText, color: overviewHealthBadgeColor),
            SettingsHeaderBadgeItem(
                text: localizedOverviewSyncBadgeText,
                color: diagnosticBadgeColor(for: syncFreshnessStatus)
            )
        ]
    }

    // MARK: Reminder header badges

    var localizedReminderHeaderPrimaryBadgeText: String {
        reminderPreferencesController.reminderPreferences.globalReminderEnabled
            ? localized("提醒已开启", "Reminders On")
            : localized("提醒已关闭", "Reminders Off")
    }

    var reminderHeaderPrimaryBadgeColor: Color {
        reminderPreferencesController.reminderPreferences.globalReminderEnabled ? .green : .secondary
    }

    var localizedReminderHeaderScheduleBadgeText: String {
        switch reminderEngine.state {
        case .idle:
            return localized("当前无待触发提醒", "No Pending Reminder")
        case .scheduled:
            return localized("下次提醒已安排", "Next Reminder Scheduled")
        case .playing:
            return localized("提醒进行中", "Reminder Running")
        case let .triggeredSilently(_, _, reason):
            switch reason {
            case .userMuted:
                return localized("已静音触发", "Triggered Silently")
            case .outputRoutePolicy:
                return localized("已因播放策略静默", "Muted by Policy")
            }
        case .disabled:
            return localized("提醒未启用", "Reminder Disabled")
        case .failed:
            return localized("提醒异常", "Reminder Issue")
        }
    }

    var reminderHeaderBadges: [SettingsHeaderBadgeItem] {
        [
            SettingsHeaderBadgeItem(text: localizedReminderHeaderPrimaryBadgeText, color: reminderHeaderPrimaryBadgeColor),
            SettingsHeaderBadgeItem(text: localizedReminderHeaderScheduleBadgeText, color: reminderStatusBadgeColor)
        ]
    }

    var reminderStatusSymbolName: String {
        switch reminderEngine.state {
        case .idle:
            return "bell.badge"
        case .scheduled:
            return "bell.fill"
        case .playing:
            return "timer.circle.fill"
        case let .triggeredSilently(_, _, reason):
            switch reason {
            case .userMuted:
                return "bell.slash.fill"
            case .outputRoutePolicy:
                return "speaker.slash.fill"
            }
        case .disabled:
            return "bell.slash.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    var reminderStatusBadgeColor: Color {
        switch reminderEngine.state {
        case .disabled:
            return .secondary
        case .failed:
            return .red
        case .idle:
            return .orange
        case .scheduled:
            return .green
        case .playing, .triggeredSilently:
            return .blue
        }
    }

    // MARK: Calendar header badges

    var calendarHeaderBadges: [SettingsHeaderBadgeItem] {
        [
            SettingsHeaderBadgeItem(text: localizedCalendarHeaderStateBadgeText, color: calendarHeaderStateBadgeColor),
            SettingsHeaderBadgeItem(text: localizedCalendarHeaderConnectionBadgeText, color: calendarHeaderConnectionBadgeColor),
            SettingsHeaderBadgeItem(text: localizedCalendarHeaderAuthorizationBadgeText, color: calendarHeaderAuthorizationBadgeColor),
            SettingsHeaderBadgeItem(text: localizedCalendarHeaderCheckedBadgeText, color: calendarHeaderCheckedBadgeColor)
        ]
    }

    var localizedCalendarHeaderStateBadgeText: String {
        switch calendarConnectionState {
        case .healthy:
            return localized("状态正常", "Healthy")
        case .authorizationRequired:
            return localized("无法访问日历", "Access Needed")
        case .connectionFailure:
            return localized("连接异常", "Connection Issue")
        }
    }

    var calendarHeaderStateBadgeColor: Color {
        switch calendarConnectionState {
        case .healthy:
            return .green
        case .authorizationRequired:
            return .orange
        case .connectionFailure:
            return .red
        }
    }

    var localizedCalendarHeaderConnectionBadgeText: String {
        switch calendarConnectionState {
        case .healthy:
            return localized("CalDAV 已连接", "CalDAV Connected")
        case .authorizationRequired:
            return localized("等待 CalDAV 检查", "CalDAV Pending")
        case .connectionFailure:
            return localized("CalDAV 读取失败", "CalDAV Failed")
        }
    }

    var calendarHeaderConnectionBadgeColor: Color {
        switch calendarConnectionState {
        case .healthy:
            return .blue
        case .authorizationRequired:
            return .secondary
        case .connectionFailure:
            return .red
        }
    }

    var localizedCalendarHeaderAuthorizationBadgeText: String {
        switch systemCalendarConnectionController.authorizationState {
        case .authorized:
            return localized("已授权", "Granted")
        case .notDetermined:
            return localized("等待授权", "Needs Access")
        case .denied:
            return localized("已拒绝", "Denied")
        case .restricted:
            return localized("访问受限", "Restricted")
        case .writeOnly:
            return localized("仅写入", "Write-only")
        case .unknown:
            return localized("状态未知", "Unknown")
        }
    }

    var calendarHeaderAuthorizationBadgeColor: Color {
        authorizationBadgeColor(for: systemCalendarConnectionController.authorizationState)
    }

    var localizedCalendarHeaderCheckedBadgeText: String {
        if let lastLoadedAt = systemCalendarConnectionController.lastLoadedAt {
            return localized(
                "\(localizedDateHeadline(for: lastLoadedAt)) 检查成功",
                "Checked \(localizedDateHeadline(for: lastLoadedAt))"
            )
        }

        return localized("等待首次检查", "Waiting for first check")
    }

    var calendarHeaderCheckedBadgeColor: Color {
        switch calendarConnectionState {
        case .healthy:
            return .green
        case .authorizationRequired:
            return .secondary
        case .connectionFailure:
            return .orange
        }
    }

    var calendarHeaderSummaryColor: Color {
        switch calendarConnectionState {
        case .healthy:
            return Color.secondary
        case .authorizationRequired, .connectionFailure:
            return Color.primary.opacity(0.82)
        }
    }

    // MARK: Calendar selection feedback colors

    var localizedCalendarSelectionFeedback: String? {
        switch systemCalendarConnectionController.selectionPersistenceState {
        case .idle:
            return nil
        case .saving:
            return localized("正在保存…", "Saving...")
        case .saved:
            return localized("已保存", "Saved")
        case .failed:
            return localized("保存失败，请重试", "Save failed, please retry")
        }
    }

    var calendarSelectionFeedbackColor: Color {
        switch systemCalendarConnectionController.selectionPersistenceState {
        case .idle:
            return .secondary
        case .saving:
            return .secondary
        case .saved:
            return Color.green.opacity(0.82)
        case .failed:
            return .red
        }
    }
}
