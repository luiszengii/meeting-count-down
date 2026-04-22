import AppKit
import SwiftUI

// MARK: - Calendar connection diagnostics snapshot

/// 日历连接诊断快照的构建与导出。
/// 这里聚合"把当前运行时状态打包成诊断文本"的所有辅助成员，
/// 高级页（AdvancedPage）通过 calendarConnectionDiagnosticSnapshot 获取快照，
/// 不会直接触碰业务层。
///
/// 2026-04-22 拆分自 Presentation.swift（见 ADR: docs/adrs/2026-04-22-presentation-split.md）
extension SettingsView {

    // MARK: Snapshot construction

    /// 诊断导出需要显式读取当前 app 元信息，方便区分"本地 Debug 版"和"GitHub Release 版"。
    var calendarConnectionDiagnosticSnapshot: CalendarConnectionDiagnosticSnapshot {
        CalendarConnectionDiagnosticSnapshot(
            generatedAt: Date(),
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            authorizationState: systemCalendarConnectionController.authorizationState,
            healthState: sourceCoordinator.state.healthState,
            lastSourceErrorMessage: sourceCoordinator.state.lastErrorMessage,
            lastSourceRefreshAt: sourceCoordinator.state.lastRefreshAt,
            lastCalendarStateLoadAt: systemCalendarConnectionController.lastLoadedAt,
            hasStoredCalendarSelection: systemCalendarConnectionController.hasStoredSelection,
            storedSelectedCalendarIDs: Array(systemCalendarConnectionController.lastLoadedStoredCalendarIDs),
            unavailableStoredCalendarIDs: Array(systemCalendarConnectionController.lastUnavailableStoredCalendarIDs),
            effectiveSelectedCalendarIDs: Array(systemCalendarConnectionController.selectedCalendarIDs),
            availableCalendars: systemCalendarConnectionController.availableCalendars
        )
    }

    // MARK: Clipboard export

    /// 把诊断文本复制到系统剪贴板，方便用户直接贴到 issue 或聊天窗口。
    func copyCalendarConnectionDiagnosticReport() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(calendarConnectionDiagnosticSnapshot.reportText, forType: .string)
    }

    // MARK: Localized diagnostic summaries

    /// "连接诊断"需要把权限、读取失败和选择失配压成一条用户化摘要，而不是直接暴露 debug label。
    var localizedCalendarConnectionDiagnosticSummary: String {
        switch systemCalendarConnectionController.authorizationState {
        case .authorized:
            break
        case .notDetermined:
            return localized("等待授予日历权限", "Calendar access is needed")
        case .denied:
            return localized("日历权限被拒绝", "Calendar access was denied")
        case .restricted:
            return localized("日历访问受限", "Calendar access is restricted")
        case .writeOnly:
            return localized("当前只有写入权限", "Calendar access is write-only")
        case .unknown:
            return localized("日历权限状态未知", "Calendar access is unknown")
        }

        if sourceCoordinator.state.lastErrorMessage != nil {
            return localized("会议读取出现问题", "Meeting reading has an issue")
        }

        switch calendarConnectionDiagnosticSnapshot.selectionDebugState {
        case "ready":
            return localized("就绪", "Ready")
        case "stored_selection_missing_from_current_calendar_list":
            return localized("已保存的日历当前不可用", "Saved calendars are unavailable")
        case "stored_selection_is_empty":
            return localized("当前保存的是空选择", "An empty selection is saved")
        case "selection_not_saved_yet":
            return localized("尚未保存日历选择", "No calendar selection is saved yet")
        default:
            return localized("状态未知", "Unknown")
        }
    }

    /// 高级页直接复用这条摘要，避免用户还没复制完整诊断前完全不知道"当前到底卡在哪一层"。
    var localizedStoredCalendarSelectionSummary: String {
        if !systemCalendarConnectionController.selectedCalendarIDs.isEmpty {
            return localized(
                "当前生效 \(systemCalendarConnectionController.selectedCalendarIDs.count) 个日历。",
                "\(systemCalendarConnectionController.selectedCalendarIDs.count) calendar(s) are active right now."
            )
        }

        if !systemCalendarConnectionController.lastUnavailableStoredCalendarIDs.isEmpty {
            return localized(
                "之前保存过的日历当前都不在系统列表里。",
                "Previously saved calendars are missing from the current system list."
            )
        }

        if systemCalendarConnectionController.hasStoredSelection {
            return localized("用户已经保存过空选择。", "An explicit empty selection was saved.")
        }

        return localized("还没有保存过日历选择。", "No calendar selection has been saved yet.")
    }

    /// 让高级页快速展示"到底枚举到了几条系统日历"。
    var localizedAvailableCalendarSummary: String {
        let count = systemCalendarConnectionController.availableCalendars.count

        if count == 0 {
            return localized("当前没有读到任何系统日历。", "No system calendars are readable right now.")
        }

        return localized("当前读到 \(count) 个系统日历。", "Currently reading \(count) system calendar(s).")
    }

    /// 高级页里的"同步和开机启动"只保留低频系统行为，不再复用概览式状态摘要。
    var localizedAdvancedSyncPanelDetail: String {
        localized(
            "查看上次同步，并控制登录后是否自动启动。",
            "Check the latest sync and control whether the app launches after login."
        )
    }

    /// 高级页里的"上次同步"改用更短的事实值，避免在同一张卡里重复"多久之前同步成功"。
    var localizedAdvancedLastSyncValue: String {
        guard let lastRefreshAt = sourceCoordinator.state.lastRefreshAt else {
            return localized("尚未同步", "Not synced yet")
        }

        return localizedDateHeadline(for: lastRefreshAt)
    }

    /// 诊断卡只保留其他页面看不到的排障事实和导出动作，不再复读概览摘要。
    var localizedAdvancedDiagnosticsPanelDetail: String {
        localized(
            "只保留排障独有信息，并支持导出完整诊断文本。",
            "Show only troubleshooting-specific facts and export the full diagnostic report."
        )
    }

    /// 高级页的"可见日历"只展示当前枚举结果，不再夹带额外判断文案。
    var localizedVisibleCalendarCountValue: String {
        let count = systemCalendarConnectionController.availableCalendars.count
        return localized("\(count) 个系统日历", "\(count) system calendar(s)")
    }
}
