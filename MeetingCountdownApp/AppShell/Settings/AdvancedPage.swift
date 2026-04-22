import AppKit
import SwiftUI

/// 高级页已从 SettingsView extension 迁移为独立 struct，实现 SettingsPage 协议。
/// didCopyCalendarDiagnostics 状态现由 AdvancedPage 自身持有。
///
/// 详见 ADR: docs/adrs/2026-04-22-settings-page-registry.md
struct AdvancedPage: SettingsPage {
    @ObservedObject var sourceCoordinator: SourceCoordinator
    @ObservedObject var systemCalendarConnectionController: SystemCalendarConnectionController
    @ObservedObject var reminderPreferencesController: ReminderPreferencesController
    @ObservedObject var launchAtLoginController: LaunchAtLoginController

    var id: SettingsTab { .advanced }
    var titleKey: (chinese: String, english: String) { ("高级", "Advanced") }

    @MainActor func body(uiLanguage: AppUILanguage) -> AnyView {
        AnyView(AdvancedPageBody(page: self, uiLanguage: uiLanguage))
    }
}

// MARK: - Body view

private struct AdvancedPageBody: View {
    let page: AdvancedPage
    let uiLanguage: AppUILanguage

    /// 复制诊断信息后的短暂反馈状态。
    @State private var didCopyCalendarDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            languagePanel
            syncPanel
            diagnosticsPanel
        }
    }

    // MARK: Localization shorthand

    private func L(_ chinese: String, _ english: String) -> String {
        localized(chinese, english, in: uiLanguage)
    }

    // MARK: Language panel

    private var languagePanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    pageIntro(
                        eyebrow: L("语言", "LANGUAGE"),
                        title: L("界面语言", "Language"),
                        detail: L("切换设置页和菜单栏文案。", "Change the text in Settings and the menu bar.")
                    )
                    Spacer(minLength: 12)
                    GlassSegmentedTabs(selection: interfaceLanguageBinding) { language in
                        language.optionLabel
                    }
                }
                .frame(minWidth: 760, alignment: .leading)

                VStack(alignment: .leading, spacing: 16) {
                    pageIntro(
                        eyebrow: L("语言", "LANGUAGE"),
                        title: L("界面语言", "Language"),
                        detail: L("切换设置页和菜单栏文案。", "Change the text in Settings and the menu bar.")
                    )
                    GlassSegmentedTabs(selection: interfaceLanguageBinding) { language in
                        language.optionLabel
                    }
                }
            }
        }
    }

    // MARK: Sync panel

    private var syncPanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 18) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        pageIntro(
                            eyebrow: L("系统", "SYSTEM"),
                            title: L("同步和开机启动", "Sync and Launch"),
                            detail: L(
                                "查看上次同步，并控制登录后是否自动启动。",
                                "Check the latest sync and control whether the app launches after login."
                            )
                        )
                        Spacer(minLength: 0)
                        syncActions
                    }
                    .frame(minWidth: 780, alignment: .leading)

                    VStack(alignment: .leading, spacing: 14) {
                        pageIntro(
                            eyebrow: L("系统", "SYSTEM"),
                            title: L("同步和开机启动", "Sync and Launch"),
                            detail: L(
                                "查看上次同步，并控制登录后是否自动启动。",
                                "Check the latest sync and control whether the app launches after login."
                            )
                        )
                        syncActions
                    }
                }

                infoRow(title: L("上次同步", "Last Sync"), value: localizedAdvancedLastSyncValue)

                preferenceDivider

                preferenceToggleRow(
                    title: L("开机启动", "Launch at Login"),
                    detail: localizedLaunchAtLoginStatusSummary,
                    isOn: Binding(
                        get: { page.launchAtLoginController.isEnabled },
                        set: { isEnabled in Task { await page.launchAtLoginController.setEnabled(isEnabled) } }
                    )
                )
                .disabled(page.launchAtLoginController.isApplyingState)

                if let lastErrorMessage = page.launchAtLoginController.lastErrorMessage {
                    warningStrip(lastErrorMessage)
                }
            }
        }
    }

    private var syncActions: some View {
        Button {
            Task { await page.sourceCoordinator.refresh(trigger: .manualRefresh) }
        } label: {
            Text(L("立即同步", "Sync Now"))
        }
        .buttonStyle(GlassPillButtonStyle(tone: .secondary))
        .disabled(page.sourceCoordinator.state.isRefreshing)
    }

    // MARK: Diagnostics panel

    private var diagnosticsPanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 18) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        pageIntro(
                            eyebrow: L("诊断", "DIAGNOSTICS"),
                            title: L("诊断信息", "Diagnostics"),
                            detail: L(
                                "只保留排障独有信息，并支持导出完整诊断文本。",
                                "Show only troubleshooting-specific facts and export the full diagnostic report."
                            )
                        )
                        Spacer(minLength: 0)
                        diagnosticsActions
                    }
                    .frame(minWidth: 780, alignment: .leading)

                    VStack(alignment: .leading, spacing: 14) {
                        pageIntro(
                            eyebrow: L("诊断", "DIAGNOSTICS"),
                            title: L("诊断信息", "Diagnostics"),
                            detail: L(
                                "只保留排障独有信息，并支持导出完整诊断文本。",
                                "Show only troubleshooting-specific facts and export the full diagnostic report."
                            )
                        )
                        diagnosticsActions
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    infoRow(title: L("当前数据源", "Active Data Source"), value: L("飞书 CalDAV / macOS 日历", "Feishu CalDAV / macOS Calendar"))
                    infoRow(title: L("接入模式", "Connection Mode"), value: L("CalDAV 单一路径", "CalDAV Only"))
                    infoRow(title: L("可见日历", "Visible Calendars"), value: localizedVisibleCalendarCountValue)
                    infoRow(title: L("连接诊断", "Connection Diagnosis"), value: localizedCalendarConnectionDiagnosticSummary)
                }

                if let lastErrorMessage = page.sourceCoordinator.state.lastErrorMessage {
                    warningStrip(lastErrorMessage)
                }
            }
        }
    }

    private var diagnosticsActions: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Button {
                copyCalendarConnectionDiagnosticReport()
                didCopyCalendarDiagnostics = true

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    didCopyCalendarDiagnostics = false
                }
            } label: {
                Text(L("复制诊断信息", "Copy Diagnostics"))
            }
            .buttonStyle(GlassPillButtonStyle(tone: .secondary))

            if didCopyCalendarDiagnostics {
                Text(L("已复制，可直接粘贴给开发者。", "Copied. Paste it directly to the developer."))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Presentation state & strings

    private var interfaceLanguageBinding: Binding<AppUILanguage> {
        Binding(
            get: { page.reminderPreferencesController.reminderPreferences.interfaceLanguage },
            set: { language in Task { await page.reminderPreferencesController.setInterfaceLanguage(language) } }
        )
    }

    private var localizedLaunchAtLoginStatusSummary: String {
        page.launchAtLoginController.statusSummary(for: uiLanguage)
    }

    private var localizedAdvancedLastSyncValue: String {
        guard let lastRefreshAt = page.sourceCoordinator.state.lastRefreshAt else {
            return L("尚未同步", "Not synced yet")
        }
        return localizedDateHeadline(for: lastRefreshAt)
    }

    private var localizedVisibleCalendarCountValue: String {
        let count = page.systemCalendarConnectionController.availableCalendars.count
        return L("\(count) 个系统日历", "\(count) system calendar(s)")
    }

    private var localizedCalendarConnectionDiagnosticSummary: String {
        let snapshot = calendarConnectionDiagnosticSnapshot

        switch page.systemCalendarConnectionController.authorizationState {
        case .authorized:
            break
        case .notDetermined:
            return L("等待授予日历权限", "Calendar access is needed")
        case .denied:
            return L("日历权限被拒绝", "Calendar access was denied")
        case .restricted:
            return L("日历访问受限", "Calendar access is restricted")
        case .writeOnly:
            return L("当前只有写入权限", "Calendar access is write-only")
        case .unknown:
            return L("日历权限状态未知", "Calendar access is unknown")
        }

        if page.sourceCoordinator.state.lastErrorMessage != nil {
            return L("会议读取出现问题", "Meeting reading has an issue")
        }

        switch snapshot.selectionDebugState {
        case "ready":
            return L("就绪", "Ready")
        case "stored_selection_missing_from_current_calendar_list":
            return L("已保存的日历当前不可用", "Saved calendars are unavailable")
        case "stored_selection_is_empty":
            return L("当前保存的是空选择", "An empty selection is saved")
        case "selection_not_saved_yet":
            return L("尚未保存日历选择", "No calendar selection is saved yet")
        default:
            return L("状态未知", "Unknown")
        }
    }

    private var calendarConnectionDiagnosticSnapshot: CalendarConnectionDiagnosticSnapshot {
        CalendarConnectionDiagnosticSnapshot(
            generatedAt: Date(),
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            authorizationState: page.systemCalendarConnectionController.authorizationState,
            healthState: page.sourceCoordinator.state.healthState,
            lastSourceErrorMessage: page.sourceCoordinator.state.lastErrorMessage,
            lastSourceRefreshAt: page.sourceCoordinator.state.lastRefreshAt,
            lastCalendarStateLoadAt: page.systemCalendarConnectionController.lastLoadedAt,
            hasStoredCalendarSelection: page.systemCalendarConnectionController.hasStoredSelection,
            storedSelectedCalendarIDs: Array(page.systemCalendarConnectionController.lastLoadedStoredCalendarIDs),
            unavailableStoredCalendarIDs: Array(page.systemCalendarConnectionController.lastUnavailableStoredCalendarIDs),
            effectiveSelectedCalendarIDs: Array(page.systemCalendarConnectionController.selectedCalendarIDs),
            availableCalendars: page.systemCalendarConnectionController.availableCalendars
        )
    }

    private func copyCalendarConnectionDiagnosticReport() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(calendarConnectionDiagnosticSnapshot.reportText, forType: .string)
    }

    private var isReminderPreferenceEditingDisabled: Bool {
        page.reminderPreferencesController.loadingState || page.reminderPreferencesController.isSavingState
    }

    // MARK: Date helper

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let englishMonthSymbols = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    private func localizedDateHeadline(for date: Date) -> String {
        let timeLine = Self.absoluteFormatter.string(from: date)
        let cal = Calendar.current
        if cal.isDateInToday(date) { return L("今天 \(timeLine)", "Today \(timeLine)") }
        if cal.isDateInTomorrow(date) { return L("明天 \(timeLine)", "Tomorrow \(timeLine)") }
        if cal.isDateInYesterday(date) { return L("昨天 \(timeLine)", "Yesterday \(timeLine)") }
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        if uiLanguage == .english {
            return "\(Self.englishMonthSymbols[max(0, min(11, month - 1))]) \(day), \(timeLine)"
        }
        let currentYear = cal.component(.year, from: Date())
        let year = cal.component(.year, from: date)
        if year == currentYear { return "\(month)月\(day)日 \(timeLine)" }
        return "\(year)年\(month)月\(day)日 \(timeLine)"
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

    private func infoRow(title: String, value: String) -> some View {
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
                Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var preferenceDivider: some View {
        Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1)
    }

    private func preferenceToggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
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

    private func preferenceToggleText(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 15, weight: .bold))
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func preferenceStateLabel(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(color.opacity(0.12)))
            .overlay(Capsule(style: .continuous).strokeBorder(color.opacity(0.18), lineWidth: 1))
    }

    private func preferenceToggleControl(isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(isReminderPreferenceEditingDisabled)
    }

    private func preferenceToggleStateText(isOn: Bool) -> String {
        if isReminderPreferenceEditingDisabled { return L("保存中", "Saving") }
        return isOn ? L("已开启", "Enabled") : L("已关闭", "Disabled")
    }

    private func preferenceToggleStateColor(isOn: Bool) -> Color {
        if isReminderPreferenceEditingDisabled { return .secondary }
        return isOn ? .green : .secondary
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
