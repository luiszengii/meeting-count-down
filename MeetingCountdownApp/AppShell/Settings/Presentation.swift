import AppKit
import SwiftUI

// MARK: - Residual presentation helpers (2026-04-22 split; 2026-04-22 trimmed for page registry)
//
// 这个文件是 2026-04-22 拆分后的残余部分。
// 2026-04-22 第二次修订（T5 页面注册表重构）后，页面特有的展示态推导已迁移至各页面 struct，
// 这里保留 SettingsView 壳层仍需的跨页辅助：
//   • 概览和提醒页 Header 文案（hero 标题、副标题）
//   • `isReminderPreferenceEditingDisabled`、`isSoundProfileEditingDisabled`（BadgePresentation 引用）
//   • `syncFreshnessStatus`（BadgePresentation 引用）
//   • 选中日历名称摘要（概览 header badge 引用）
//   • 倒计时和音频行（header audio badge 引用）
//   • CalendarConnectionPresentationState、CalendarSourceGroup、CalendarSourceSection 文件级类型
//   • SettingsTab、ReminderCountdownMode 枚举及过渡动画扩展
//
// 已迁出内容（页面特有逻辑）：
//   • 概览页展示态推导  → OverviewPage.swift
//   • 日历页展示态推导  → CalendarPage.swift
//   • 提醒页展示态推导  → RemindersPage.swift
//   • 音频页展示态推导  → AudioPage.swift
//   • 高级页展示态推导  → AdvancedPage.swift
//
// 详见 ADR: docs/adrs/2026-04-22-settings-page-registry.md
// 详见 ADR: docs/adrs/2026-04-22-presentation-split.md

extension SettingsView {

    // MARK: Reminder editing guard flags

    var isReminderPreferenceEditingDisabled: Bool {
        reminderPreferencesController.loadingState || reminderPreferencesController.isSavingState
    }

    var isSoundProfileEditingDisabled: Bool {
        soundProfileLibraryController.loadingState
            || soundProfileLibraryController.isImportingState
            || soundProfileLibraryController.isApplyingState
    }

    // MARK: Sync freshness

    var syncFreshnessStatus: DiagnosticCheckStatus {
        SyncFreshnessDiagnostic.status(
            lastSuccessfulRefreshAt: sourceCoordinator.state.lastRefreshAt,
            now: Date()
        )
    }

    // MARK: Overview page header strings

    /// 概览页头部文案由 Header.swift 的 currentHeaderContent 引用。
    var localizedOverviewPageTitle: String {
        localized("会议提醒概览", "Meeting Reminder Overview")
    }

    var localizedOverviewPageSubtitle: String {
        localized(
            "管理日历连接、提醒状态、音频播放与同步健康度。",
            "Manage calendar connection, reminder status, audio playback, and sync health."
        )
    }

    // MARK: Sound / countdown line (used by audio header badge)

    var currentSoundProfileLine: String {
        if let selectedSoundProfile = soundProfileLibraryController.selectedSoundProfile {
            return "\(selectedSoundProfile.displayName) · \(localizedDurationLine(for: selectedSoundProfile.duration))"
        }

        return localized("默认提醒音效", "Default reminder sound")
    }

    var selectedSoundProfileName: String {
        soundProfileLibraryController.selectedSoundProfile?.displayName
            ?? localized("默认提醒音效", "Default reminder sound")
    }

    var isCountdownFollowingSelectedSound: Bool {
        reminderPreferencesController.reminderPreferences.countdownOverrideSeconds == nil
    }

    // MARK: Reminder page header strings

    var localizedReminderPageTitle: String {
        localized("提醒", "Reminders")
    }

    var localizedReminderPageSubtitle: String {
        localized(
            "只看提醒是否会执行、何时开始，以及声音会怎么处理。",
            "Focus on whether reminders will run, when they start, and how sound behaves."
        )
    }

    // MARK: Sync freshness badge text (used by SettingsBadgePresentation)

    var localizedSyncFreshnessBadgeText: String {
        switch syncFreshnessStatus {
        case .idle:
            return localized("未检查", "Idle")
        case .pending:
            return localized("检查中", "Checking")
        case .passed:
            return localized("正常", "Fresh")
        case .warning:
            return localized("偏旧", "Stale")
        case .failed:
            return localized("失败", "Failed")
        }
    }

    // MARK: Calendar configuration state (used by SettingsBadgePresentation)

    var hasAddedCalDAVAccount: Bool {
        systemCalendarConnectionController.availableCalendars.contains(where: \.isSuggestedByDefault)
            || systemCalendarConnectionController.hasSelectedCalendars
    }

    var isCalendarConfigurationComplete: Bool {
        hasAddedCalDAVAccount
            && systemCalendarConnectionController.authorizationState == .authorized
            && systemCalendarConnectionController.hasSelectedCalendars
    }

    var calendarConnectionState: CalendarConnectionPresentationState {
        let authorizationState = systemCalendarConnectionController.authorizationState

        guard authorizationState.allowsReading else {
            return .authorizationRequired
        }

        if case .failed = sourceCoordinator.state.healthState {
            let fallbackMessage = localized(
                "请检查网络、账号信息或服务器地址后重试",
                "Check your network, account information, or server address and try again"
            )
            return .connectionFailure(message: sourceCoordinator.state.lastErrorMessage ?? fallbackMessage)
        }

        if let errorMessage = systemCalendarConnectionController.errorMessage {
            return .connectionFailure(message: errorMessage)
        }

        return .healthy
    }

    var calendarLastCheckedSummary: String {
        guard let lastLoadedAt = systemCalendarConnectionController.lastLoadedAt else {
            return localized("尚未完成首次检查", "No successful check yet")
        }

        return localizedDateHeadline(for: lastLoadedAt)
    }

    // MARK: Selected calendar names detail (used by overview header badge)

    var selectedCalendarDisplayNames: [String] {
        let selectedIDs = systemCalendarConnectionController.selectedCalendarIDs
        let names = systemCalendarConnectionController.availableCalendars
            .filter { selectedIDs.contains($0.id) }
            .map(\.title)

        if !names.isEmpty {
            return Array(names.prefix(3))
        }

        if selectedIDs.isEmpty {
            return []
        }

        return [localized("\(selectedIDs.count) 个已保存日历", "\(selectedIDs.count) saved calendar(s)")]
    }

    // MARK: Overview reminder / audio status (used by SettingsBadgePresentation)

    var localizedOverviewAudioStatusTitle: String {
        if !reminderPreferencesController.reminderPreferences.globalReminderEnabled {
            return localized("不会播放", "Playback Off")
        }

        if reminderPreferencesController.reminderPreferences.isMuted {
            return localized("静音模式", "Muted")
        }

        if reminderPreferencesController.reminderPreferences.playSoundOnlyWhenHeadphonesConnected {
            return localized("仅耳机播放", "Headphones Only")
        }

        return localized("正常播放", "Audible")
    }

    var localizedOverviewReminderStatusTitle: String {
        reminderPreferencesController.reminderPreferences.globalReminderEnabled
            ? localized("已开启", "Enabled")
            : localized("已关闭", "Disabled")
    }

    // MARK: Grid layout helper (used by SettingsBadgePresentation for overview header)

    func responsiveCardColumns(minimum: CGFloat, maximum: CGFloat = 360) -> [GridItem] {
        [
            GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: 16, alignment: .topLeading)
        ]
    }

    // MARK: Scheduled reminder context helper

    var currentScheduledReminderContext: ScheduledReminderContext? {
        switch reminderEngine.state {
        case let .scheduled(context),
             let .playing(context, _),
             let .triggeredSilently(context, _, _):
            return context
        case .idle, .disabled, .failed:
            return nil
        }
    }
}

// MARK: - File-level types

/// 日历页把"连接正常 / 权限异常 / 连接异常"抽成显式展示态，
/// 这样页面结构可以围绕任务组织，而不是把多种判断散在 View 里。
enum CalendarConnectionPresentationState: Equatable {
    case healthy
    case authorizationRequired
    case connectionFailure(message: String)
}

/// 日历列表按来源分组，帮助用户先理解"这些日历来自哪里"，再决定是否纳入提醒。
enum CalendarSourceGroup: String, CaseIterable, Identifiable {
    case feishu
    case iCloud
    case subscribed
    case other

    var id: String { rawValue }
}

/// 搜索后的结果仍然要保留分组顺序，因此用一个轻量 section 模型描述。
struct CalendarSourceSection: Identifiable, Equatable {
    let group: CalendarSourceGroup
    let calendars: [SystemCalendarDescriptor]

    var id: String { group.id }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case overview
    case calendar
    case reminders
    case audio
    case advanced

    var id: String { rawValue }

    func title(for language: AppUILanguage) -> String {
        switch self {
        case .overview:
            return language == .english ? "Overview" : "概览"
        case .calendar:
            return language == .english ? "Calendar" : "日历"
        case .reminders:
            return language == .english ? "Reminders" : "提醒"
        case .audio:
            return language == .english ? "Audio" : "音频"
        case .advanced:
            return language == .english ? "Advanced" : "高级"
        }
    }
}

/// `ReminderCountdownMode` 只服务于设置页表达"当前时长来自哪里"，
/// 它不会直接改变提醒引擎规则，只负责把现有偏好映射成两种可理解的 UI 选择。
enum ReminderCountdownMode: String, CaseIterable, Identifiable {
    case followSound
    case manual

    var id: String { rawValue }

    func title(for language: AppUILanguage) -> String {
        switch self {
        case .followSound:
            return language == .english ? "Follow Sound" : "跟随音频"
        case .manual:
            return language == .english ? "Manual" : "手动固定"
        }
    }
}

extension AppUILanguage {
    /// 语言选项使用各自原生名字，避免用户找不到切换入口。
    var optionLabel: String {
        switch self {
        case .simplifiedChinese:
            return "中文"
        case .english:
            return "English"
        }
    }
}

/// 切换设置页 tab 时用轻微下移 + 淡入，避免内容硬切。
struct SettingsPageTransitionModifier: ViewModifier {
    let opacity: Double
    let offsetY: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: offsetY)
    }
}

extension AnyTransition {
    static var settingsPageSwap: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SettingsPageTransitionModifier(opacity: 0, offsetY: 8),
                identity: SettingsPageTransitionModifier(opacity: 1, offsetY: 0)
            ),
            removal: .opacity
        )
    }
}
