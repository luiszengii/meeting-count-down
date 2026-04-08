import AppKit
import SwiftUI

/// `MenuBarContentView` 现在承担“命令中心”而不是“状态复读机”的角色。
/// 它会先回答“现在发生了什么”，再给出一条最合适的下一步动作，
/// 让菜单栏弹层更像真正的 menubar utility，而不是临时调试面板。
struct MenuBarContentView: View {
    /// 菜单内容需要观察会议读取状态。
    @ObservedObject var sourceCoordinator: SourceCoordinator
    /// 这个桥接控制器专门用来登记 SwiftUI 官方 `openSettings` 动作，
    /// 让外层的 `NSStatusItem` 控制器也能通过同一条官方路径打开设置页。
    let settingsSceneOpenController: SettingsSceneOpenController
    /// 真正打开设置窗口的动作改成由外部显式注入，方便 `NSStatusItem` 和 SwiftUI 场景共用。
    let openSettingsAction: () -> Void

    /// SwiftUI 通过 `body` 描述当前菜单内容应该如何由状态渲染出来。
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerBlock
            primaryActionButton
            secondaryActionRow
            footerActionRow
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(
            SettingsSceneActionRegistrar(
                settingsSceneOpenController: settingsSceneOpenController
            )
        )
    }

    /// 顶部信息块只保留“当前状态 + 一句上下文”。
    /// 这里故意不再重复同一句状态，避免把最宝贵的视觉空间浪费在复读上。
    @ViewBuilder
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: statusSymbolName)
                    .foregroundStyle(statusAccentColor)

                Text(headerTitle)
                    .font(.headline.weight(.semibold))
            }

            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                compactBadge(text: connectionBadgeText, color: connectionBadgeColor)

                if sourceCoordinator.state.isRefreshing {
                    compactBadge(text: "正在刷新", color: .blue)
                } else if let nextMeeting = sourceCoordinator.state.nextMeeting {
                    compactBadge(
                        text: sourceCoordinator.meetingStartLine(for: nextMeeting),
                        color: .secondary
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    /// 主按钮永远回答“下一步做什么”。
    /// 它的文案和行为都会随着“无会议 / 有会议 / 未配置 / 刷新失败”而变化。
    @ViewBuilder
    private var primaryActionButton: some View {
        let action = primaryAction

        Button {
            performPrimaryAction(action)
        } label: {
            Label(action.title, systemImage: action.symbolName)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    /// 次级动作保留真正高频的恢复路径，但视觉上降一级。
    @ViewBuilder
    private var secondaryActionRow: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await sourceCoordinator.refresh(trigger: .manualRefresh)
                }
            } label: {
                Label("立即刷新", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(sourceCoordinator.state.isRefreshing)

            Button {
                openSettingsWindow()
            } label: {
                Label("打开设置", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    /// 退出动作保留，但明确降级到底部，避免和主操作抢注意力。
    @ViewBuilder
    private var footerActionRow: some View {
        HStack {
            Spacer()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "xmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    /// 当前弹层主标题。
    private var headerTitle: String {
        if let nextMeeting = sourceCoordinator.state.nextMeeting {
            return nextMeeting.title
        }

        switch sourceCoordinator.state.healthState {
        case .ready:
            return "当前暂无可提醒会议"
        case .unconfigured:
            return "接入尚未完成"
        case .warning:
            return "同步状态需要关注"
        case .failed:
            return "当前无法读取会议"
        }
    }

    /// 当前弹层副标题只补一句上下文，不重复主标题。
    private var headerSubtitle: String {
        if let nextMeeting = sourceCoordinator.state.nextMeeting {
            return sourceCoordinator.meetingStartLine(for: nextMeeting)
        }

        if let lastErrorMessage = sourceCoordinator.state.lastErrorMessage {
            return lastErrorMessage
        }

        return sourceCoordinator.state.healthState.summary
    }

    /// 当前头部图标语义。
    private var statusSymbolName: String {
        if sourceCoordinator.state.nextMeeting != nil {
            return "calendar.badge.clock"
        }

        return sourceCoordinator.state.healthState.symbolName
    }

    /// 头部图标强调色。
    private var statusAccentColor: Color {
        switch sourceCoordinator.state.healthState {
        case .ready:
            return sourceCoordinator.state.nextMeeting == nil ? .secondary : .blue
        case .warning:
            return .orange
        case .unconfigured, .failed:
            return .red
        }
    }

    /// 当前连接状态标签，尽量短，方便在小弹层里快速扫读。
    private var connectionBadgeText: String {
        switch sourceCoordinator.state.healthState {
        case .ready(let message), .warning(let message):
            if let matchedCount = extractLeadingInteger(from: message) {
                return "已连接 \(matchedCount) 个日历"
            }

            return sourceCoordinator.state.healthState.shortLabel

        case .unconfigured, .failed:
            return sourceCoordinator.state.healthState.shortLabel
        }
    }

    /// 当前连接状态颜色语义。
    private var connectionBadgeColor: Color {
        switch sourceCoordinator.state.healthState {
        case .ready:
            return .green
        case .warning:
            return .orange
        case .unconfigured, .failed:
            return .red
        }
    }

    /// 把当前最佳下一步动作压成纯值，避免 UI 结构里散落一堆条件分支。
    private var primaryAction: PrimaryAction {
        if let nextMeeting = sourceCoordinator.state.nextMeeting {
            if let preferredLink = preferredMeetingLink(for: nextMeeting) {
                return PrimaryAction(
                    title: preferredLink.kind == .vc ? "加入会议" : "查看会议详情",
                    symbolName: preferredLink.kind == .vc ? "video.circle.fill" : "link.circle.fill",
                    handler: {
                        NSWorkspace.shared.open(preferredLink.url)
                    }
                )
            }

            return PrimaryAction(
                title: "打开“日历”查看安排",
                symbolName: "calendar",
                handler: openCalendarApp
            )
        }

        switch sourceCoordinator.state.healthState {
        case .unconfigured:
            return PrimaryAction(
                title: "完成接入设置",
                symbolName: "slider.horizontal.3",
                handler: openSettingsWindow
            )

        case .failed:
            return PrimaryAction(
                title: "打开“日历”检查同步",
                symbolName: "calendar",
                handler: openCalendarApp
            )

        case .warning:
            return PrimaryAction(
                title: "重新检查同步状态",
                symbolName: "arrow.clockwise.circle",
                handler: {
                    Task {
                        await sourceCoordinator.refresh(trigger: .manualRefresh)
                    }
                }
            )

        case .ready:
            return PrimaryAction(
                title: "打开“日历”检查同步",
                symbolName: "calendar",
                handler: openCalendarApp
            )
        }
    }

    /// 当前如果存在视频会议或详情链接，就优先让弹层提供直达入口。
    private func preferredMeetingLink(for meeting: MeetingRecord) -> MeetingLink? {
        if let videoLink = meeting.links.first(where: { $0.kind == .vc }) {
            return videoLink
        }

        if let detailLink = meeting.links.first(where: { $0.kind == .eventDetail }) {
            return detailLink
        }

        return meeting.links.first
    }

    /// 主按钮只负责继续执行纯值里的处理逻辑。
    private func performPrimaryAction(_ action: PrimaryAction) {
        action.handler()
    }

    /// 打开系统日历应用，让用户沿着真实数据源去确认同步是否完成。
    private func openCalendarApp() {
        if let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: nil
            )
            return
        }

        if let fallbackURL = URL(string: "ical://") {
            NSWorkspace.shared.open(fallbackURL)
        }
    }

    /// 设置按钮只负责把动作继续交给外部。
    /// 真正的窗口创建和前台化都由壳层控制器统一处理，避免视图自己知道 AppKit 细节。
    private func openSettingsWindow() {
        openSettingsAction()
    }

    /// 从健康状态摘要里提取“已连接 N 个系统日历”的数字，供 badge 复用。
    private func extractLeadingInteger(from message: String) -> Int? {
        let digits = message.split(whereSeparator: { !$0.isNumber }).first ?? ""
        return Int(digits)
    }

    /// 小尺寸状态标签入口。
    @ViewBuilder
    private func compactBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.14))
            )
            .foregroundStyle(color)
    }
}

/// `PrimaryAction` 把命令面板里唯一的主按钮抽成纯值。
/// 这样视图可以围绕一个“下一步动作”组织，而不是在按钮结构里散落复杂分支。
private struct PrimaryAction {
    let title: String
    let symbolName: String
    let handler: () -> Void
}

/// `SettingsSceneActionRegistrar` 是一个零尺寸辅助视图。
/// 它唯一的职责是在菜单弹层真正进入 SwiftUI 渲染树后，读取环境里的 `openSettings`
/// 并把这条官方动作登记到共享桥接控制器里，避免 AppKit 层继续走过时的 selector 打开设置。
private struct SettingsSceneActionRegistrar: View {
    @Environment(\.openSettings) private var openSettings

    let settingsSceneOpenController: SettingsSceneOpenController

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                let openSettingsAction = openSettings
                settingsSceneOpenController.register {
                    openSettingsAction()
                }
            }
    }
}
