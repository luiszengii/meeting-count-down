import SwiftUI

/// 这个文件负责日历接入页。
/// 它把一次性的 CalDAV 配置步骤和长期维护的系统日历选择拆开，
/// 避免用户在同一个区域里同时理解“怎么接入”和“现在选了什么”。
extension SettingsView {
    var calendarPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            calendarSetupPanel

            if !isCalendarConfigurationComplete || isCalendarConfigurationExpanded {
                calendarStepsPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            calendarSourcePanel
        }
    }

    var calendarSetupPanel: some View {
        GlassPanel(cornerRadius: 30, padding: 20, overlayOpacity: 0.14) {
            VStack(alignment: .leading, spacing: 16) {
                pageIntro(
                    eyebrow: localized("日历接入", "CALENDAR"),
                    title: localized("连接飞书日历", "Connect Feishu Calendar"),
                    detail: calendarConfigurationSummaryLine
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 14) {
                        calendarSetupStatusBlock
                        Spacer(minLength: 12)
                        calendarSetupActions
                    }
                    .frame(minWidth: 760, alignment: .leading)

                    VStack(alignment: .leading, spacing: 14) {
                        calendarSetupStatusBlock
                        calendarSetupActions
                    }
                }
            }
        }
    }

    /// 接入总览只回答“现在接好了没有”，具体步骤单独放到下一张卡里。
    var calendarSetupStatusBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                GlassBadge(
                    text: isCalendarConfigurationComplete
                        ? localized("已完成", "Complete")
                        : localized("待处理", "Needs Setup"),
                    color: isCalendarConfigurationComplete ? .green : .orange
                )

                GlassBadge(
                    text: localizedAuthorizationBadgeText(for: systemCalendarConnectionController.authorizationState),
                    color: authorizationBadgeColor(for: systemCalendarConnectionController.authorizationState)
                )
            }

            Text(localizedCalendarSelectionSummary)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    /// 接入摘要卡把维护动作放在一起，避免状态和步骤说明互相挤压。
    var calendarSetupActions: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await systemCalendarConnectionController.refreshState()
                    await sourceCoordinator.refresh(trigger: .manualRefresh)
                }
            } label: {
                Text(localized("重新检查", "Re-check"))
            }
            .buttonStyle(GlassPillButtonStyle(tone: .secondary))
            .disabled(systemCalendarConnectionController.isLoadingState || systemCalendarConnectionController.isRequestingAccess)

            if isCalendarConfigurationComplete {
                Button {
                    withAnimation(GlassMotion.page) {
                        isCalendarConfigurationExpanded.toggle()
                    }
                } label: {
                    Text(isCalendarConfigurationExpanded
                        ? localized("收起接入步骤", "Hide Setup Steps")
                        : localized("查看接入步骤", "Show Setup Steps"))
                }
                .buttonStyle(GlassPillButtonStyle(tone: .secondary))
            }
        }
    }

    var calendarStepsPanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 16) {
                pageIntro(
                    eyebrow: localized("接入步骤", "SETUP STEPS"),
                    title: localized("按这四步检查连接", "Check the connection in four steps"),
                    detail: localized("首次配置时照着做；日后排查也优先看这里。", "Use these steps for first-time setup and future troubleshooting.")
                )

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

    var calendarSourcePanel: some View {
        GlassPanel(cornerRadius: 30, padding: 20, overlayOpacity: 0.14) {
            VStack(alignment: .leading, spacing: 18) {
                pageIntro(
                    eyebrow: localized("日历列表", "CALENDARS"),
                    title: localized("选择要提醒的日历", "Choose calendars for reminders"),
                    detail: localized("只有勾选的日历会参与提醒。", "Only selected calendars will be used for reminders.")
                )

                HStack(alignment: .center, spacing: 10) {
                    GlassBadge(
                        text: localizedAuthorizationBadgeText(for: systemCalendarConnectionController.authorizationState),
                        color: authorizationBadgeColor(for: systemCalendarConnectionController.authorizationState)
                    )

                    if let lastLoadedAt = systemCalendarConnectionController.lastLoadedAt {
                        Text("\(localized("最近检查", "Last checked")) · \(Self.absoluteFormatter.string(from: lastLoadedAt))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastErrorMessage = systemCalendarConnectionController.lastErrorMessage {
                    warningStrip(lastErrorMessage)
                }

                switch systemCalendarConnectionController.authorizationState {
                case .authorized:
                    if systemCalendarConnectionController.isLoadingState {
                        ProgressView(localized("正在读取本地日历…", "Reading local calendars..."))
                            .controlSize(.small)
                    } else if systemCalendarConnectionController.availableCalendars.isEmpty {
                        emptyStatePanel(
                            title: localized("当前还没有可读取的系统日历", "No readable calendars yet"),
                            detail: localized(
                                "先确认飞书日历已经同步到 macOS“日历”，再回来刷新。",
                                "Make sure Feishu Calendar is synced to macOS Calendar, then refresh here."
                            )
                        )
                    } else {
                        LazyVGrid(columns: responsiveCardColumns(minimum: 320, maximum: 420), spacing: 14) {
                            ForEach(systemCalendarConnectionController.availableCalendars) { calendar in
                                calendarRow(for: calendar)
                            }
                        }
                    }

                case .notDetermined:
                    Button {
                        Task {
                            await systemCalendarConnectionController.requestCalendarAccess()
                        }
                    } label: {
                        Label(localized("授予日历权限", "Grant Calendar Access"), systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(GlassPillButtonStyle(tone: .primary))
                    .disabled(systemCalendarConnectionController.isRequestingAccess)

                case .denied, .restricted, .writeOnly, .unknown:
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            openCalendarPrivacySettings()
                        } label: {
                            Text(localized("打开系统设置", "Open System Settings"))
                        }
                        .buttonStyle(GlassPillButtonStyle(tone: .primary))

                        Text(localized("先修复权限问题，再回来重新检查本地日历源。", "Repair the permission first, then come back and re-check the local calendar source."))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
