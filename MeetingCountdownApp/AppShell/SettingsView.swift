import AppKit
import SwiftUI

/// `SettingsView` 现在只承载 CalDAV 单一路径需要的配置和状态总览。
/// 它不直接操作 EventKit 原始对象，而是通过 `SystemCalendarConnectionController`
/// 和 `SourceCoordinator` 暴露出来的聚合状态驱动界面。
struct SettingsView: View {
    /// 设置窗口和菜单栏共享同一份数据源协调层。
    @ObservedObject var sourceCoordinator: SourceCoordinator
    /// CalDAV / 系统日历路线的真实配置状态和动作入口。
    @ObservedObject var systemCalendarConnectionController: SystemCalendarConnectionController
    /// 设置页自己把真实窗口登记到这里，供菜单栏入口复用。
    let settingsWindowController: SettingsWindowController

    /// 统一渲染设置窗口内容。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                caldavGuideGroup
                systemCalendarConfigurationGroup
                appStatusGroup
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .background(
            SettingsWindowAccessor { window in
                settingsWindowController.register(window: window)
                settingsWindowController.activateKnownWindow()
            }
        )
    }

    @ViewBuilder
    private var caldavGuideGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("唯一接入路径")
                    .font(.headline)

                Text("当前版本只支持 `CalDAV -> macOS Calendar -> 本地 app`。请先在飞书日历里生成 CalDAV 配置，再到 macOS“日历”应用添加“其他 CalDAV 账户 -> 手动”，最后回到这里授权并选择目标日历。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("如果这里还没有看到飞书日历，通常说明系统日历尚未同步完成，或者 macOS Calendar 里的账户还没添加成功。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 当前设置页的核心区域：权限状态、候选日历以及日历选择。
    @ViewBuilder
    private var systemCalendarConfigurationGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("CalDAV / 系统日历配置")
                        .font(.headline)

                    Spacer()

                    Button {
                        Task {
                            await systemCalendarConnectionController.refreshState()
                            await sourceCoordinator.refresh(trigger: .manualRefresh)
                        }
                    } label: {
                        Label("重新检查", systemImage: "arrow.clockwise")
                    }
                    .disabled(systemCalendarConnectionController.isLoadingState || systemCalendarConnectionController.isRequestingAccess)

                    badge(
                        text: systemCalendarConnectionController.authorizationState.badgeText,
                        color: authorizationBadgeColor(for: systemCalendarConnectionController.authorizationState)
                    )
                }

                Text(systemCalendarConnectionController.authorizationState.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let lastLoadedAt = systemCalendarConnectionController.lastLoadedAt {
                    LabeledContent("最近检查", value: Self.absoluteFormatter.string(from: lastLoadedAt))
                }

                if let lastErrorMessage = systemCalendarConnectionController.lastErrorMessage {
                    Text(lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                switch systemCalendarConnectionController.authorizationState {
                case .authorized:
                    LabeledContent("选择状态", value: systemCalendarConnectionController.selectionSummary)

                    if systemCalendarConnectionController.isLoadingState {
                        ProgressView("正在读取系统日历…")
                            .controlSize(.small)
                    } else if systemCalendarConnectionController.availableCalendars.isEmpty {
                        Text("当前没有可读取的系统日历。请先在 macOS Calendar 中添加飞书 CalDAV 账户，再回到这里重新检查。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
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
                        Label("授权访问日历", systemImage: "calendar.badge.plus")
                    }
                    .disabled(systemCalendarConnectionController.isRequestingAccess)

                    Text("只有在你显式点击按钮后，应用才会触发系统日历权限框。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .denied, .restricted, .writeOnly, .unknown:
                    Button {
                        openCalendarPrivacySettings()
                    } label: {
                        Label("打开系统设置", systemImage: "gearshape")
                    }

                    Text("修复权限后，可以回到这里重新检查并选择要纳入提醒的系统日历。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 当前应用运行态摘要，帮助用户区分“权限问题”“日历选择问题”和“当前没有会议”。
    @ViewBuilder
    private var appStatusGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("当前应用状态")
                        .font(.headline)

                    Spacer()

                    Button {
                        Task {
                            await sourceCoordinator.refresh(trigger: .manualRefresh)
                        }
                    } label: {
                        Label("立即刷新会议", systemImage: "arrow.clockwise")
                    }
                    .disabled(sourceCoordinator.state.isRefreshing)
                }

                LabeledContent("活动数据源", value: "CalDAV / 系统日历")
                LabeledContent("健康状态", value: sourceCoordinator.state.healthState.summary)
                LabeledContent("最近刷新", value: sourceCoordinator.lastRefreshLine)

                if let nextMeeting = sourceCoordinator.state.nextMeeting {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("下一场会议")
                            .font(.caption.weight(.medium))
                        Text(nextMeeting.title)
                            .font(.body.weight(.medium))
                        Text(sourceCoordinator.meetingStartLine(for: nextMeeting))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("当前还没有可用于提醒的下一场会议。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let lastErrorMessage = sourceCoordinator.state.lastErrorMessage {
                    Text(lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 单条系统日历候选行，展示推荐标记、来源说明和可勾选状态。
    @ViewBuilder
    private func calendarRow(for calendar: SystemCalendarDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Toggle(
                    isOn: Binding(
                        get: {
                            systemCalendarConnectionController.selectedCalendarIDs.contains(calendar.id)
                        },
                        set: { isSelected in
                            Task {
                                await systemCalendarConnectionController.setCalendarSelection(
                                    calendarID: calendar.id,
                                    isSelected: isSelected
                                )
                            }
                        }
                    )
                ) {
                    Text(calendar.title)
                        .font(.body.weight(.medium))
                }
                .toggleStyle(.checkbox)

                if calendar.isSuggestedByDefault {
                    badge(text: "推荐", color: .green)
                }
            }

            Text(calendar.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    /// 授权状态标签使用更贴近日历流程的颜色。
    private func authorizationBadgeColor(for state: SystemCalendarAuthorizationState) -> Color {
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

    /// 给单色标签提供一个更轻量的通用渲染入口。
    @ViewBuilder
    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.18))
            )
            .foregroundStyle(color)
    }

    /// 打开 macOS 隐私设置里的日历权限页，帮助用户修复已拒绝的状态。
    private func openCalendarPrivacySettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }

    /// 设置页复用的绝对时间格式。
    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
