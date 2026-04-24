import SwiftUI

/// 日历页已从 SettingsView extension 迁移为独立 struct，实现 SettingsPage 协议。
/// 页内展开状态（calendarStepsPanel）和搜索文本现在由 CalendarPage 自身持有。
///
/// 详见 ADR: docs/adrs/2026-04-22-settings-page-registry.md
struct CalendarPage: SettingsPage {
    @ObservedObject var systemCalendarConnectionController: SystemCalendarConnectionController
    @ObservedObject var sourceCoordinator: SourceCoordinator

    var id: SettingsTab { .calendar }
    var titleKey: (chinese: String, english: String) { ("日历", "Calendar") }

    @MainActor func body(uiLanguage: AppUILanguage) -> AnyView {
        AnyView(CalendarPageBody(page: self, uiLanguage: uiLanguage))
    }
}

// MARK: - Body view

private struct CalendarPageBody: View {
    let page: CalendarPage
    let uiLanguage: AppUILanguage

    /// 接入说明面板是否展开：首次打开时由日历连接完整性决定，之后可由用户切换。
    @State private var isCalendarConfigurationExpanded = true
    @State private var hasInitializedExpansion = false
    @State private var calendarSearchQuery = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            calendarConnectionPanel
            calendarSelectionPanel
            calendarSelectionAlerts
            calendarGroupList
            calendarInfoPanel

            if isCalendarConfigurationExpanded {
                calendarStepsPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            guard !hasInitializedExpansion else { return }
            hasInitializedExpansion = true
            isCalendarConfigurationExpanded = !isCalendarConfigurationComplete
        }
        .onChange(of: isCalendarConfigurationComplete) { _, isComplete in
            withAnimation(GlassMotion.page) {
                isCalendarConfigurationExpanded = !isComplete
            }
        }
    }

    // MARK: Localization shorthand

    private func localized(_ chinese: String, _ english: String) -> String {
        FeishuMeetingCountdown.localized(chinese, english, in: uiLanguage)
    }

    // MARK: Connection panel

    private var calendarConnectionPanel: some View {
        GlassPanel(cornerRadius: 28, padding: 20, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 16) {
                Text(localized("日历连接", "Calendar Connection"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.95))

                Text(localizedCalendarConnectionHeadline)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(localizedCalendarConnectionDetail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                switch calendarConnectionState {
                case .healthy:
                    VStack(alignment: .leading, spacing: 12) {
                        infoRow(title: localized("连接方式", "Connection"), value: "CalDAV")
                        infoRow(title: localized("授权状态", "Access"), value: localizedCalendarAuthorizationValue)
                        infoRow(title: localized("最近检查", "Last Checked"), value: calendarLastCheckedSummary)
                    }
                case .authorizationRequired:
                    EmptyView()
                case let .connectionFailure(message):
                    infoRow(title: localized("错误详情", "Error Detail"), value: message)
                }

                calendarConnectionActions
            }
        }
    }

    private var calendarConnectionActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                calendarPrimaryConnectionAction
                calendarSecondaryConnectionAction
            }
            .frame(minWidth: 360, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                calendarPrimaryConnectionAction
                calendarSecondaryConnectionAction
            }
        }
    }

    private var calendarPrimaryConnectionAction: some View {
        Button(action: primaryCalendarConnectionAction) {
            Text(primaryCalendarConnectionActionTitle)
        }
        .buttonStyle(GlassPillButtonStyle(tone: .secondary))
        .disabled(page.systemCalendarConnectionController.loadingState || page.systemCalendarConnectionController.isRequestingAccess)
    }

    private var calendarSecondaryConnectionAction: some View {
        Button(action: secondaryCalendarConnectionAction) {
            Text(secondaryCalendarConnectionActionTitle)
        }
        .buttonStyle(GlassPillButtonStyle(tone: calendarConnectionState == .authorizationRequired ? .primary : .secondary))
        .disabled(page.systemCalendarConnectionController.loadingState || page.systemCalendarConnectionController.isRequestingAccess)
    }

    private var primaryCalendarConnectionActionTitle: String {
        switch calendarConnectionState {
        case .healthy, .authorizationRequired: return localized("重新检查连接", "Check Again")
        case .connectionFailure: return localized("重试连接", "Retry Connection")
        }
    }

    private var secondaryCalendarConnectionActionTitle: String {
        switch calendarConnectionState {
        case .authorizationRequired: return localized("打开系统设置", "Open System Settings")
        case .healthy, .connectionFailure: return localized("查看接入说明", "View Setup Guide")
        }
    }

    private func primaryCalendarConnectionAction() { refreshCalendarConnection() }

    private func secondaryCalendarConnectionAction() {
        switch calendarConnectionState {
        case .authorizationRequired: openCalendarPrivacySettings()
        case .healthy, .connectionFailure: showCalendarSetupGuide()
        }
    }

    // MARK: Selection panel

    private var calendarSelectionPanel: some View {
        GlassPanel(cornerRadius: 28, padding: 20, overlayOpacity: 0.1) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(localized("选择参与提醒的日历", "Choose Calendars for Reminders"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))

                    Text(localized(
                        "仅勾选日历中的会议会触发提醒",
                        "Only meetings in selected calendars can trigger reminders"
                    ))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(localizedCalendarSelectionCountSummary)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 12)

                        if let feedback = localizedCalendarSelectionFeedback {
                            Text(feedback)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(calendarSelectionFeedbackColor)
                                .fixedSize()
                        }
                    }
                    .frame(minWidth: 620, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(localizedCalendarSelectionCountSummary)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        if let feedback = localizedCalendarSelectionFeedback {
                            Text(feedback)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(calendarSelectionFeedbackColor)
                                .fixedSize()
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        HStack(spacing: 10) {
                            Button { selectAllCalendars() } label: {
                                Text(localized("全选", "Select All"))
                            }
                            .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                            .disabled(!isCalendarSelectionInteractionEnabled)

                            Button { clearAllCalendars() } label: {
                                Text(localized("清空", "Clear"))
                            }
                            .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                            .disabled(!isCalendarSelectionInteractionEnabled)
                        }

                        Spacer(minLength: 16)
                        calendarSearchField.frame(width: 260)
                    }
                    .frame(minWidth: 720, alignment: .leading)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Button { selectAllCalendars() } label: {
                                Text(localized("全选", "Select All"))
                            }
                            .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                            .disabled(!isCalendarSelectionInteractionEnabled)

                            Button { clearAllCalendars() } label: {
                                Text(localized("清空", "Clear"))
                            }
                            .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                            .disabled(!isCalendarSelectionInteractionEnabled)
                        }
                        calendarSearchField
                    }
                }
            }
        }
    }

    private var calendarSearchField: some View {
        TextField(localized("搜索日历…", "Search calendars…"), text: $calendarSearchQuery)
            .textFieldStyle(.roundedBorder)
            .disabled(!isCalendarSelectionInteractionEnabled)
    }

    // MARK: Alerts

    @ViewBuilder
    private var calendarSelectionAlerts: some View {
        if shouldShowCalendarPermissionAlert {
            statusCallout(
                title: localized("无法访问日历", "Calendar Access Is Unavailable"),
                detail: localized(
                    "应用尚未获得日历访问权限，当前无法读取会议并触发提醒。",
                    "The app hasn't been granted calendar access, so it can't read meetings or trigger reminders."
                ),
                tone: .error,
                actions: [
                    StatusCalloutAction(title: localized("打开系统设置", "Open System Settings"), tone: .primary, handler: openCalendarPrivacySettings),
                    StatusCalloutAction(title: localized("重新检查连接", "Check Again"), tone: .secondary, handler: refreshCalendarConnection)
                ]
            )
        }

        if case let .connectionFailure(message) = calendarConnectionState {
            statusCallout(
                title: localized("无法连接到飞书日历", "Unable to Connect to Feishu Calendar"),
                detail: message,
                tone: .error,
                actions: [
                    StatusCalloutAction(title: localized("重试连接", "Retry Connection"), tone: .primary, handler: refreshCalendarConnection),
                    StatusCalloutAction(title: localized("查看接入说明", "View Setup Guide"), tone: .secondary, handler: showCalendarSetupGuide)
                ]
            )
        }

        if shouldShowCalendarUnavailableAlert {
            statusCallout(
                title: localized("没有发现可用日历", "No Available Calendars Were Found"),
                detail: localized(
                    "当前账户下没有可用于提醒的日历，请重新检查连接或确认账户内容。",
                    "No calendars that can be used for reminders were found. Re-check the connection or confirm the account contents."
                ),
                tone: .error,
                actions: [
                    StatusCalloutAction(title: localized("重新扫描", "Scan Again"), tone: .primary, handler: refreshCalendarConnection),
                    StatusCalloutAction(title: localized("查看帮助", "View Help"), tone: .secondary, handler: showCalendarSetupGuide)
                ]
            )
        }

        if shouldShowNoSelectedCalendarsAlert {
            statusCallout(
                title: localized("尚未选择任何日历", "No Calendars Are Selected Yet"),
                detail: localized("当前不会对任何会议触发提醒。", "No meetings will trigger reminders right now."),
                tone: .warning,
                actions: [
                    StatusCalloutAction(title: localized("全选", "Select All"), tone: .secondary, handler: selectAllCalendars)
                ]
            )
        }

        if shouldShowCalendarSaveFailureAlert {
            statusCallout(
                title: localized("保存失败", "Save Failed"),
                detail: localized(
                    "未能更新日历选择，已恢复到上一次保存状态。",
                    "The calendar selection couldn't be updated and has been restored to the last saved state."
                ),
                tone: .error,
                actions: [
                    StatusCalloutAction(title: localized("重试", "Try Again"), tone: .secondary, handler: refreshCalendarConnection)
                ]
            )
        }
    }

    // MARK: Calendar list

    @ViewBuilder
    private var calendarGroupList: some View {
        if page.systemCalendarConnectionController.loadingState {
            GlassPanel(cornerRadius: 24, padding: 18, overlayOpacity: 0.08) {
                ProgressView(localized("正在读取本地日历…", "Reading local calendars..."))
                    .controlSize(.small)
            }
        } else if !page.systemCalendarConnectionController.authorizationState.allowsReading {
            GlassPanel(cornerRadius: 24, padding: 18, overlayOpacity: 0.08) {
                Text(localized(
                    "完成授权后，这里会按来源分组显示可参与提醒的日历。",
                    "Available calendars will appear here by source after access is granted."
                ))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(0.65)
        } else if page.systemCalendarConnectionController.availableCalendars.isEmpty {
            EmptyView()
        } else if filteredCalendarSections.isEmpty {
            emptyStatePanel(
                title: localized("未找到匹配的日历", "No Matching Calendars Found"),
                detail: localized("请尝试其他关键词。", "Try a different keyword.")
            )
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(filteredCalendarSections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(localizedCalendarGroupTitle(for: section.group))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.9))

                        GlassPanel(cornerRadius: 24, padding: 0, overlayOpacity: 0.08) {
                            VStack(spacing: 0) {
                                ForEach(Array(section.calendars.enumerated()), id: \.element.id) { index, calendar in
                                    calendarRow(for: calendar)
                                    if index < section.calendars.count - 1 {
                                        Rectangle()
                                            .fill(Color.white.opacity(0.08))
                                            .frame(height: 1)
                                            .padding(.leading, 44)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .disabled(!isCalendarSelectionInteractionEnabled)
            .opacity(isCalendarSelectionInteractionEnabled ? 1 : 0.55)
        }
    }

    // MARK: Info & steps panels

    private var calendarInfoPanel: some View {
        GlassPanel(cornerRadius: 24, padding: 18, overlayOpacity: 0.08) {
            VStack(alignment: .leading, spacing: 8) {
                Text(localized("说明", "Notes"))
                    .font(.system(size: 16, weight: .bold))
                Text(localized(
                    "勾选后会自动保存。仅勾选日历中的会议会触发提醒。",
                    "Selections are saved automatically. Only meetings in selected calendars can trigger reminders."
                ))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                Text(localized(
                    "系统日历、节假日和生日日历通常不建议开启会议提醒。",
                    "System calendars, holiday calendars, and birthday calendars usually shouldn't trigger meeting reminders."
                ))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var calendarStepsPanel: some View {
        GlassPanel(cornerRadius: 26, padding: 18, overlayOpacity: 0.08) {
            VStack(alignment: .leading, spacing: 16) {
                Text(localized("接入说明", "Setup Guide"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Text(localized(
                    "首次配置或排查连接问题时，优先按下面四步检查。",
                    "Use these four steps first when setting up or troubleshooting the connection."
                ))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    setupStepRow(
                        title: localized("在飞书里生成 CalDAV 凭证", "Generate CalDAV credentials in Feishu"),
                        detail: localized("复制用户名、专用密码和服务器地址。", "Copy the username, app password, and server address."),
                        isComplete: true
                    )
                    setupStepRow(
                        title: localized("在 macOS 日历里添加\u{201C}其他 CalDAV 账户\u{201D}", "Add an Other CalDAV Account in macOS Calendar"),
                        detail: localized("选择\u{201C}手动\u{201D}，再粘贴刚才的凭证。", "Choose manual setup, then paste the credentials."),
                        isComplete: hasAddedCalDAVAccount
                    )
                    setupStepRow(
                        title: localized("授予本应用日历访问权限", "Grant this app calendar access"),
                        detail: localizedAuthorizationSummary(for: page.systemCalendarConnectionController.authorizationState),
                        isComplete: page.systemCalendarConnectionController.authorizationState == .authorized
                    )
                    setupStepRow(
                        title: localized("选择需要参与提醒的日历", "Select the calendars that should count"),
                        detail: localizedCalendarSelectionSummary,
                        isComplete: page.systemCalendarConnectionController.hasSelectedCalendars
                    )
                }
            }
        }
    }

    // MARK: Calendar row

    private func calendarRow(for calendar: SystemCalendarDescriptor) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(
                isOn: Binding(
                    get: { page.systemCalendarConnectionController.selectedCalendarIDs.contains(calendar.id) },
                    set: { isSelected in
                        Task {
                            await page.systemCalendarConnectionController.setCalendarSelection(
                                calendarID: calendar.id,
                                isSelected: isSelected
                            )
                        }
                    }
                )
            ) { EmptyView() }
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

    private func calendarAccessoryTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.primary.opacity(0.74))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.12)))
    }

    // MARK: Actions

    private func refreshCalendarConnection() {
        Task {
            await page.systemCalendarConnectionController.refreshState()
            await page.sourceCoordinator.refresh(trigger: .manualRefresh)
        }
    }

    private func showCalendarSetupGuide() {
        withAnimation(GlassMotion.page) {
            isCalendarConfigurationExpanded = true
        }
    }

    private func selectAllCalendars() {
        let calendarIDs = Set(page.systemCalendarConnectionController.availableCalendars.map(\.id))
        Task { await page.systemCalendarConnectionController.setSelectedCalendarIDs(calendarIDs) }
    }

    private func clearAllCalendars() {
        Task { await page.systemCalendarConnectionController.setSelectedCalendarIDs([]) }
    }

    private func openCalendarPrivacySettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(settingsURL)
    }

    // MARK: Presentation state

    private var calendarConnectionState: CalendarConnectionPresentationState {
        let authorizationState = page.systemCalendarConnectionController.authorizationState
        guard authorizationState.allowsReading else { return .authorizationRequired }

        if case .failed = page.sourceCoordinator.state.healthState {
            let fallback = localized("请检查网络、账号信息或服务器地址后重试", "Check your network, account information, or server address and try again")
            return .connectionFailure(message: page.sourceCoordinator.state.lastErrorMessage ?? fallback)
        }

        if let errorMessage = page.systemCalendarConnectionController.errorMessage {
            return .connectionFailure(message: errorMessage)
        }

        return .healthy
    }

    private var isCalendarConfigurationComplete: Bool {
        hasAddedCalDAVAccount
            && page.systemCalendarConnectionController.authorizationState == .authorized
            && page.systemCalendarConnectionController.hasSelectedCalendars
    }

    private var hasAddedCalDAVAccount: Bool {
        page.systemCalendarConnectionController.availableCalendars.contains(where: \.isSuggestedByDefault)
            || page.systemCalendarConnectionController.hasSelectedCalendars
    }

    private var isCalendarSelectionInteractionEnabled: Bool {
        page.systemCalendarConnectionController.authorizationState.allowsReading
            && !page.systemCalendarConnectionController.loadingState
            && !page.systemCalendarConnectionController.isRequestingAccess
    }

    private var shouldShowCalendarPermissionAlert: Bool {
        !page.systemCalendarConnectionController.authorizationState.allowsReading
    }

    private var shouldShowCalendarUnavailableAlert: Bool {
        page.systemCalendarConnectionController.authorizationState.allowsReading
            && !page.systemCalendarConnectionController.loadingState
            && page.systemCalendarConnectionController.availableCalendars.isEmpty
    }

    private var shouldShowNoSelectedCalendarsAlert: Bool {
        page.systemCalendarConnectionController.authorizationState.allowsReading
            && !page.systemCalendarConnectionController.availableCalendars.isEmpty
            && page.systemCalendarConnectionController.selectedCalendarIDs.isEmpty
    }

    private var shouldShowCalendarSaveFailureAlert: Bool {
        if case .failed = page.systemCalendarConnectionController.selectionPersistenceState { return true }
        return false
    }

    // MARK: Calendar string helpers

    private var calendarLastCheckedSummary: String {
        guard let lastLoadedAt = page.systemCalendarConnectionController.lastLoadedAt else {
            return localized("尚未完成首次检查", "No successful check yet")
        }
        return localizedDateHeadline(for: lastLoadedAt)
    }

    private var localizedCalendarConnectionHeadline: String {
        switch calendarConnectionState {
        case .healthy:
            return localized("飞书日历连接正常，可读取会议并用于提醒", "Feishu Calendar is connected and can be used for reminders")
        case .authorizationRequired:
            return localized("无法访问日历", "Calendar Access Is Unavailable")
        case .connectionFailure:
            return localized("无法连接到飞书日历", "Unable to Connect to Feishu Calendar")
        }
    }

    private var localizedCalendarConnectionDetail: String {
        switch calendarConnectionState {
        case .healthy:
            return localized("当前连接方式为 CalDAV，系统日历读取正常。", "The app is using CalDAV and can read macOS Calendar normally.")
        case .authorizationRequired:
            return localized("应用尚未获得日历访问权限，当前无法读取会议并触发提醒。", "The app doesn't have calendar access yet, so it can't read meetings or trigger reminders.")
        case let .connectionFailure(message):
            return message
        }
    }

    private var localizedCalendarAuthorizationValue: String {
        switch page.systemCalendarConnectionController.authorizationState {
        case .authorized: return localized("已授权", "Granted")
        case .notDetermined: return localized("未授权", "Not Granted Yet")
        case .denied: return localized("已拒绝", "Denied")
        case .restricted: return localized("访问受限", "Restricted")
        case .writeOnly: return localized("仅写入", "Write-only")
        case .unknown: return localized("状态未知", "Unknown")
        }
    }

    private var localizedCalendarSelectionCountSummary: String {
        localized(
            "已选择 \(page.systemCalendarConnectionController.selectedCalendarIDs.count) 个，共 \(page.systemCalendarConnectionController.availableCalendars.count) 个可用",
            "\(page.systemCalendarConnectionController.selectedCalendarIDs.count) selected, \(page.systemCalendarConnectionController.availableCalendars.count) available"
        )
    }

    private var localizedCalendarSelectionFeedback: String? {
        switch page.systemCalendarConnectionController.selectionPersistenceState {
        case .idle: return nil
        case .saving: return localized("正在保存…", "Saving...")
        case .saved: return localized("已保存", "Saved")
        case .failed: return localized("保存失败，请重试", "Save failed, please retry")
        }
    }

    private var calendarSelectionFeedbackColor: Color {
        switch page.systemCalendarConnectionController.selectionPersistenceState {
        case .idle, .saving: return .secondary
        case .saved: return Color.green.opacity(0.82)
        case .failed: return .red
        }
    }

    private var localizedCalendarSelectionSummary: String {
        let count = page.systemCalendarConnectionController.selectedCalendarIDs.count
        if count == 0 { return localized("尚未选择系统日历", "No calendar selected") }
        return localized("已选 \(count) 个日历", "\(count) calendar(s) selected")
    }

    private func localizedAuthorizationSummary(for state: SystemCalendarAuthorizationState) -> String {
        switch state {
        case .authorized: return localized("已授权，可以读取日历。", "Access granted. Calendar can be read.")
        case .notDetermined: return localized("还没授予日历权限。", "Calendar access hasn't been granted yet.")
        case .denied: return localized("日历权限被拒绝，请去系统设置打开。", "Calendar access was denied. Turn it on in System Settings.")
        case .restricted: return localized("日历权限受限，暂时无法读取。", "Calendar access is restricted right now.")
        case .writeOnly: return localized("当前只能写入，不能读取日历。", "Write-only access is available, so events can't be read.")
        case .unknown: return localized("暂时无法确认日历权限状态。", "The Calendar permission state couldn't be confirmed.")
        }
    }

    // MARK: Calendar list helpers

    private var filteredCalendarSections: [CalendarSourceSection] {
        let query = calendarSearchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let calendars = page.systemCalendarConnectionController.availableCalendars.filter { calendar in
            guard !query.isEmpty else { return true }
            let candidates = [
                calendar.title,
                calendar.sourceTitle,
                localizedCalendarSourceTypeLabel(calendar.sourceTypeLabel),
                localizedCalendarGroupTitle(for: calendarSourceGroup(for: calendar))
            ]
            return candidates.contains { $0.lowercased().contains(query) }
        }

        return CalendarSourceGroup.allCases.compactMap { group in
            let grouped = calendars.filter { calendarSourceGroup(for: $0) == group }
            guard !grouped.isEmpty else { return nil }
            return CalendarSourceSection(group: group, calendars: grouped)
        }
    }

    private var calendarTitleDuplicateCounts: [String: Int] {
        Dictionary(
            page.systemCalendarConnectionController.availableCalendars.map { calendar in
                (calendar.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), 1)
            },
            uniquingKeysWith: +
        )
    }

    private func localizedCalendarDisplayName(for calendar: SystemCalendarDescriptor) -> String {
        let normalizedTitle = calendar.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let duplicateCount = calendarTitleDuplicateCounts[normalizedTitle, default: 0]
        guard duplicateCount > 1 else { return calendar.title }
        let suffix = localizedCalendarDisambiguationSuffix(for: calendar)
        return localized("\(calendar.title)（\(suffix)）", "\(calendar.title) (\(suffix))")
    }

    private func localizedCalendarDisambiguationSuffix(for calendar: SystemCalendarDescriptor) -> String {
        switch calendarSourceGroup(for: calendar) {
        case .feishu: return localized("飞书", "Feishu")
        case .iCloud: return "iCloud"
        case .subscribed: return localized("订阅", "Subscribed")
        case .other:
            if calendar.sourceTypeLabel == "生日" { return localized("生日", "Birthdays") }
            if !calendar.sourceTitle.isEmpty { return calendar.sourceTitle }
            return localizedCalendarSourceTypeLabel(calendar.sourceTypeLabel)
        }
    }

    private func localizedCalendarSubtitle(for calendar: SystemCalendarDescriptor) -> String {
        let sourceTypeLabel = localizedCalendarSourceTypeLabel(calendar.sourceTypeLabel)
        if calendar.sourceTitle.isEmpty { return sourceTypeLabel }
        return "\(calendar.sourceTitle) · \(sourceTypeLabel)"
    }

    private func localizedCalendarAccessoryTag(for calendar: SystemCalendarDescriptor) -> String? {
        if calendar.isSuggestedByDefault { return localized("主日历", "Primary") }
        if calendar.sourceTypeLabel == "生日" { return localized("生日", "Birthdays") }
        return nil
    }

    private func localizedCalendarGroupTitle(for group: CalendarSourceGroup) -> String {
        switch group {
        case .feishu: return localized("飞书", "Feishu")
        case .iCloud: return "iCloud"
        case .subscribed: return localized("订阅日历", "Subscribed Calendars")
        case .other: return localized("其他", "Other")
        }
    }

    private func calendarSourceGroup(for calendar: SystemCalendarDescriptor) -> CalendarSourceGroup {
        let normalized = calendar.sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("caldav.feishu.cn") || normalized.contains("feishu") { return .feishu }
        switch calendar.sourceTypeLabel {
        case "iCloud": return .iCloud
        case "订阅": return .subscribed
        default: return .other
        }
    }

    private func localizedCalendarSourceTypeLabel(_ label: String) -> String {
        switch label {
        case "本地": return localized("本地", "Local")
        case "订阅": return localized("订阅", "Subscribed")
        case "生日": return localized("生日", "Birthdays")
        case "其他": return localized("其他", "Other")
        default: return label
        }
    }

    // MARK: Shared component helpers (inlined to avoid SettingsView dependency)

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

    private func statusCallout(
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
                            Button(action: action.handler) { Text(action.title) }
                                .buttonStyle(GlassPillButtonStyle(tone: action.tone))
                        }
                    }
                    .frame(minWidth: 480, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(actions) { action in
                            Button(action: action.handler) { Text(action.title) }
                                .buttonStyle(GlassPillButtonStyle(tone: action.tone))
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(palette.background))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
    }

    private func emptyStatePanel(title: String, detail: String) -> some View {
        GlassCard(cornerRadius: 24, padding: 16, tintOpacity: 0.14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 16, weight: .bold))
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func setupStepRow(title: String, detail: String, isComplete: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isComplete ? Color.green : Color.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Date helper

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let englishMonthSymbols = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    private func localizedDateHeadline(for date: Date) -> String {
        let timeLine = Self.absoluteFormatter.string(from: date)
        let cal = Calendar.current
        if cal.isDateInToday(date) { return localized("今天 \(timeLine)", "Today \(timeLine)") }
        if cal.isDateInTomorrow(date) { return localized("明天 \(timeLine)", "Tomorrow \(timeLine)") }
        if cal.isDateInYesterday(date) { return localized("昨天 \(timeLine)", "Yesterday \(timeLine)") }
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
}
