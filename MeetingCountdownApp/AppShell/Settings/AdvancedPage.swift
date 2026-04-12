import SwiftUI

/// 这个文件负责高级页。
/// 这里承接语言、同步和诊断等低频维护项，使它们不再和高频设置混在一起。
extension SettingsView {
    var advancedPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 22) {
                    languagePanel
                        .frame(width: 260)

                    syncPanel
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 18) {
                    languagePanel
                    syncPanel
                }
            }

            diagnosticsPanel
        }
    }

    var languagePanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 16) {
                pageIntro(
                    eyebrow: localized("语言", "LANGUAGE"),
                    title: localized("界面语言", "Language"),
                    detail: localized("切换设置页和菜单栏文案。", "Change the text in Settings and the menu bar.")
                )

                GlassSegmentedTabs(selection: interfaceLanguageBinding) { language in
                    language.optionLabel
                }
            }
        }
    }

    var syncPanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 18) {
                pageIntro(
                    eyebrow: localized("同步与启动", "SYNC"),
                    title: localized("同步和开机启动", "Sync and Launch"),
                    detail: localizedSyncFreshnessSummary
                )

                HStack(alignment: .center, spacing: 10) {
                    GlassBadge(text: localizedSyncFreshnessBadgeText, color: diagnosticBadgeColor(for: syncFreshnessStatus))

                    Text("\(localized("最近成功读取", "Last Successful Read")) · \(localizedLastRefreshLine)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                infoRow(title: localized("新鲜度摘要", "Freshness Summary"), value: localizedSyncFreshnessSummary)

                preferenceDivider

                preferenceToggleRow(
                    title: localized("开机启动", "Launch at Login"),
                    detail: localizedLaunchAtLoginStatusSummary,
                    isOn: Binding(
                        get: { launchAtLoginController.isEnabled },
                        set: { isEnabled in
                            Task {
                                await launchAtLoginController.setEnabled(isEnabled)
                            }
                        }
                    )
                )
                .disabled(launchAtLoginController.isApplyingState)

                if let lastErrorMessage = launchAtLoginController.lastErrorMessage {
                    warningStrip(lastErrorMessage)
                }
            }
        }
    }

    var diagnosticsPanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    pageIntro(
                        eyebrow: localized("诊断", "DIAGNOSTICS"),
                        title: localized("诊断信息", "Diagnostics"),
                        detail: localized("这里会显示数据源、日历接入状态和可导出的排查信息。", "See data source, calendar setup, and exportable debug details here.")
                    )

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 10) {
                            Button {
                                Task {
                                    await sourceCoordinator.refresh(trigger: .manualRefresh)
                                }
                            } label: {
                                Text(localized("立即刷新", "Refresh Now"))
                            }
                            .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                            .disabled(sourceCoordinator.state.isRefreshing)

                            Button {
                                copyCalendarConnectionDiagnosticReport()
                                didCopyCalendarDiagnostics = true

                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                                    didCopyCalendarDiagnostics = false
                                }
                            } label: {
                                Text(localized("复制诊断信息", "Copy Diagnostics"))
                            }
                            .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                        }

                        if didCopyCalendarDiagnostics {
                            Text(localized("已复制，可直接粘贴给开发者。", "Copied. Paste it directly to the developer."))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    infoRow(title: localized("当前数据源", "Active Data Source"), value: localized("飞书 CalDAV / macOS 日历", "Feishu CalDAV / macOS Calendar"))
                    infoRow(title: localized("健康状态", "Health State"), value: localizedHealthStateSummary)
                    infoRow(title: localized("权限状态", "Permission State"), value: localizedAuthorizationSummary(for: systemCalendarConnectionController.authorizationState))
                    infoRow(title: localized("已保存选择", "Stored Selection"), value: localizedStoredCalendarSelectionSummary)
                    infoRow(title: localized("可见日历", "Visible Calendars"), value: localizedAvailableCalendarSummary)
                    infoRow(title: localized("接入调试态", "Setup Debug State"), value: calendarConnectionDiagnosticSnapshot.selectionDebugState)
                    infoRow(title: localized("提醒状态", "Reminder State"), value: localizedReminderStateSummary)
                }

                Text(localizedReminderStateDetailLine)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                if let lastErrorMessage = sourceCoordinator.state.lastErrorMessage {
                    warningStrip(lastErrorMessage)
                }
            }
        }
    }
}
