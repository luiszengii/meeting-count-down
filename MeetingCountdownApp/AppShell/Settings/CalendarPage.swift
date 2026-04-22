import SwiftUI

/// 这个文件负责“日历”页。
/// 新版结构把页面收束成三个核心任务：确认连接、选择参与提醒的日历、在异常时快速修复；
/// 因此它不再承载概览式 hero，也不再把接入说明和日历管理混在一块。
extension SettingsView {
    var calendarPage: some View {
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
    }

    /// “日历连接”模块只回答连接本身是否正常，以及用户下一步应该点哪个动作修复。
    var calendarConnectionPanel: some View {
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

    /// 日历选择区承接计数、自动保存反馈、批量操作和搜索。
    var calendarSelectionPanel: some View {
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
                            Button {
                                selectAllCalendars()
                            } label: {
                                Text(localized("全选", "Select All"))
                            }
                            .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                            .disabled(!isCalendarSelectionInteractionEnabled)

                            Button {
                                clearAllCalendars()
                            } label: {
                                Text(localized("清空", "Clear"))
                            }
                            .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                            .disabled(!isCalendarSelectionInteractionEnabled)
                        }

                        Spacer(minLength: 16)

                        calendarSearchField
                            .frame(width: 260)
                    }
                    .frame(minWidth: 720, alignment: .leading)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Button {
                                selectAllCalendars()
                            } label: {
                                Text(localized("全选", "Select All"))
                            }
                            .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                            .disabled(!isCalendarSelectionInteractionEnabled)

                            Button {
                                clearAllCalendars()
                            } label: {
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

    var calendarSearchField: some View {
        TextField(localized("搜索日历…", "Search calendars…"), text: $calendarSearchQuery)
            .textFieldStyle(.roundedBorder)
            .disabled(!isCalendarSelectionInteractionEnabled)
    }

    /// 条件异常态集中放在选择区后面，避免用户一边扫列表一边猜“为什么不生效”。
    @ViewBuilder
    var calendarSelectionAlerts: some View {
        if shouldShowCalendarPermissionAlert {
            statusCallout(
                title: localized("无法访问日历", "Calendar Access Is Unavailable"),
                detail: localized(
                    "应用尚未获得日历访问权限，当前无法读取会议并触发提醒。",
                    "The app hasn't been granted calendar access, so it can't read meetings or trigger reminders."
                ),
                tone: .error,
                actions: [
                    StatusCalloutAction(
                        title: localized("打开系统设置", "Open System Settings"),
                        tone: .primary,
                        handler: openCalendarPrivacySettings
                    ),
                    StatusCalloutAction(
                        title: localized("重新检查连接", "Check Again"),
                        tone: .secondary,
                        handler: refreshCalendarConnection
                    )
                ]
            )
        }

        if case let .connectionFailure(message) = calendarConnectionState {
            statusCallout(
                title: localized("无法连接到飞书日历", "Unable to Connect to Feishu Calendar"),
                detail: message,
                tone: .error,
                actions: [
                    StatusCalloutAction(
                        title: localized("重试连接", "Retry Connection"),
                        tone: .primary,
                        handler: refreshCalendarConnection
                    ),
                    StatusCalloutAction(
                        title: localized("查看接入说明", "View Setup Guide"),
                        tone: .secondary,
                        handler: showCalendarSetupGuide
                    )
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
                    StatusCalloutAction(
                        title: localized("重新扫描", "Scan Again"),
                        tone: .primary,
                        handler: refreshCalendarConnection
                    ),
                    StatusCalloutAction(
                        title: localized("查看帮助", "View Help"),
                        tone: .secondary,
                        handler: showCalendarSetupGuide
                    )
                ]
            )
        }

        if shouldShowNoSelectedCalendarsAlert {
            statusCallout(
                title: localized("尚未选择任何日历", "No Calendars Are Selected Yet"),
                detail: localized(
                    "当前不会对任何会议触发提醒。",
                    "No meetings will trigger reminders right now."
                ),
                tone: .warning,
                actions: [
                    StatusCalloutAction(
                        title: localized("全选", "Select All"),
                        tone: .secondary,
                        handler: selectAllCalendars
                    )
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
                    StatusCalloutAction(
                        title: localized("重试", "Try Again"),
                        tone: .secondary,
                        handler: refreshCalendarConnection
                    )
                ]
            )
        }
    }

    /// 日历列表按来源分组，并且保持搜索后仍然按同一顺序展示。
    @ViewBuilder
    var calendarGroupList: some View {
        if systemCalendarConnectionController.loadingState {
            GlassPanel(cornerRadius: 24, padding: 18, overlayOpacity: 0.08) {
                ProgressView(localized("正在读取本地日历…", "Reading local calendars..."))
                    .controlSize(.small)
            }
        } else if !systemCalendarConnectionController.authorizationState.allowsReading {
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
        } else if systemCalendarConnectionController.availableCalendars.isEmpty {
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

    /// 底部说明区明确提示自动保存语义和不建议开启的日历类型。
    var calendarInfoPanel: some View {
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

    /// 查看接入说明时，帮助面板仍然复用原来的四步结构，但放到页面底部做按需展开。
    var calendarStepsPanel: some View {
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
                        title: localized("在 macOS 日历里添加“其他 CalDAV 账户”", "Add an Other CalDAV Account in macOS Calendar"),
                        detail: localized("选择“手动”，再粘贴刚才的凭证。", "Choose manual setup, then paste the credentials."),
                        isComplete: hasAddedCalDAVAccount
                    )
                    setupStepRow(
                        title: localized("授予本应用日历访问权限", "Grant this app calendar access"),
                        detail: localizedAuthorizationSummary(for: systemCalendarConnectionController.authorizationState),
                        isComplete: systemCalendarConnectionController.authorizationState == .authorized
                    )
                    setupStepRow(
                        title: localized("选择需要参与提醒的日历", "Select the calendars that should count"),
                        detail: localizedCalendarSelectionSummary,
                        isComplete: systemCalendarConnectionController.hasSelectedCalendars
                    )
                }
            }
        }
    }

    var calendarConnectionActions: some View {
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

    var calendarPrimaryConnectionAction: some View {
        Button(action: primaryCalendarConnectionAction) {
            Text(primaryCalendarConnectionActionTitle)
        }
        .buttonStyle(GlassPillButtonStyle(tone: .secondary))
        .disabled(systemCalendarConnectionController.loadingState || systemCalendarConnectionController.isRequestingAccess)
    }

    var calendarSecondaryConnectionAction: some View {
        Button(action: secondaryCalendarConnectionAction) {
            Text(secondaryCalendarConnectionActionTitle)
        }
        .buttonStyle(GlassPillButtonStyle(tone: calendarConnectionState == .authorizationRequired ? .primary : .secondary))
        .disabled(systemCalendarConnectionController.loadingState || systemCalendarConnectionController.isRequestingAccess)
    }

    var primaryCalendarConnectionActionTitle: String {
        switch calendarConnectionState {
        case .healthy, .authorizationRequired:
            return localized("重新检查连接", "Check Again")
        case .connectionFailure:
            return localized("重试连接", "Retry Connection")
        }
    }

    var secondaryCalendarConnectionActionTitle: String {
        switch calendarConnectionState {
        case .authorizationRequired:
            return localized("打开系统设置", "Open System Settings")
        case .healthy, .connectionFailure:
            return localized("查看接入说明", "View Setup Guide")
        }
    }

    var isCalendarSelectionInteractionEnabled: Bool {
        systemCalendarConnectionController.authorizationState.allowsReading
            && !systemCalendarConnectionController.loadingState
            && !systemCalendarConnectionController.isRequestingAccess
    }

    /// 统一收口“重新检查连接”动作，避免多个按钮各自维护一份异步链路。
    func refreshCalendarConnection() {
        Task {
            await systemCalendarConnectionController.refreshState()
            await sourceCoordinator.refresh(trigger: .manualRefresh)
        }
    }

    func showCalendarSetupGuide() {
        withAnimation(GlassMotion.page) {
            isCalendarConfigurationExpanded = true
        }
    }

    func primaryCalendarConnectionAction() {
        refreshCalendarConnection()
    }

    func secondaryCalendarConnectionAction() {
        switch calendarConnectionState {
        case .authorizationRequired:
            openCalendarPrivacySettings()
        case .healthy, .connectionFailure:
            showCalendarSetupGuide()
        }
    }

    func selectAllCalendars() {
        let calendarIDs = Set(systemCalendarConnectionController.availableCalendars.map(\.id))

        Task {
            await systemCalendarConnectionController.setSelectedCalendarIDs(calendarIDs)
        }
    }

    func clearAllCalendars() {
        Task {
            await systemCalendarConnectionController.setSelectedCalendarIDs([])
        }
    }
}
