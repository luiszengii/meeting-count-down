import SwiftUI

/// 这个文件负责高级页。
/// 这里承接语言、同步和诊断等低频维护项，使它们不再和高频设置混在一起。
extension SettingsView {
    var advancedPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            languagePanel
            syncPanel
            diagnosticsPanel
        }
    }

    var languagePanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    pageIntro(
                        eyebrow: localized("语言", "LANGUAGE"),
                        title: localized("界面语言", "Language"),
                        detail: localized("切换设置页和菜单栏文案。", "Change the text in Settings and the menu bar.")
                    )

                    Spacer(minLength: 12)

                    GlassSegmentedTabs(selection: interfaceLanguageBinding) { language in
                        language.optionLabel
                    }
                }
                .frame(minWidth: 760, alignment: .leading)

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
    }

    var syncPanel: some View {
        GlassPanel(cornerRadius: 28, padding: 18, overlayOpacity: 0.12) {
            VStack(alignment: .leading, spacing: 18) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        pageIntro(
                            eyebrow: localized("系统", "SYSTEM"),
                            title: localized("同步和开机启动", "Sync and Launch"),
                            detail: localizedAdvancedSyncPanelDetail
                        )

                        Spacer(minLength: 0)

                        syncActions
                    }
                    .frame(minWidth: 780, alignment: .leading)

                    VStack(alignment: .leading, spacing: 14) {
                        pageIntro(
                            eyebrow: localized("系统", "SYSTEM"),
                            title: localized("同步和开机启动", "Sync and Launch"),
                            detail: localizedAdvancedSyncPanelDetail
                        )

                        syncActions
                    }
                }

                infoRow(title: localized("上次同步", "Last Sync"), value: localizedAdvancedLastSyncValue)

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
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        pageIntro(
                            eyebrow: localized("诊断", "DIAGNOSTICS"),
                            title: localized("诊断信息", "Diagnostics"),
                            detail: localizedAdvancedDiagnosticsPanelDetail
                        )

                        Spacer(minLength: 0)

                        diagnosticsActions
                    }
                    .frame(minWidth: 780, alignment: .leading)

                    VStack(alignment: .leading, spacing: 14) {
                        pageIntro(
                            eyebrow: localized("诊断", "DIAGNOSTICS"),
                            title: localized("诊断信息", "Diagnostics"),
                            detail: localizedAdvancedDiagnosticsPanelDetail
                        )

                        diagnosticsActions
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    infoRow(title: localized("当前数据源", "Active Data Source"), value: localized("飞书 CalDAV / macOS 日历", "Feishu CalDAV / macOS Calendar"))
                    infoRow(title: localized("接入模式", "Connection Mode"), value: localized("CalDAV 单一路径", "CalDAV Only"))
                    infoRow(title: localized("可见日历", "Visible Calendars"), value: localizedVisibleCalendarCountValue)
                    infoRow(title: localized("连接诊断", "Connection Diagnosis"), value: localizedCalendarConnectionDiagnosticSummary)
                }

                if let lastErrorMessage = sourceCoordinator.state.lastErrorMessage {
                    warningStrip(lastErrorMessage)
                }
            }
        }
    }

    /// 同步动作留在系统行为卡，避免“立即同步”继续和诊断导出混在一起。
    var syncActions: some View {
        Button {
            Task {
                await sourceCoordinator.refresh(trigger: .manualRefresh)
            }
        } label: {
            Text(localized("立即同步", "Sync Now"))
        }
        .buttonStyle(GlassPillButtonStyle(tone: .secondary))
        .disabled(sourceCoordinator.state.isRefreshing)
    }

    /// 诊断动作在宽窄布局里都复用同一组按钮和复制反馈，避免两套逻辑漂移。
    var diagnosticsActions: some View {
        VStack(alignment: .trailing, spacing: 8) {
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

            if didCopyCalendarDiagnostics {
                Text(localized("已复制，可直接粘贴给开发者。", "Copied. Paste it directly to the developer."))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
