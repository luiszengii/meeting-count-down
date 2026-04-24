import AppKit
import SwiftUI

/// `MenuBarContentView` 改成更接近控制中心的结构：
/// 顶部是当前会议与主操作，中间是倒计时主卡，底部是轻量菜单动作。
/// 它仍只消费协调层状态，不在这里重写提醒逻辑。
struct MenuBarContentView: View {
    @ObservedObject var sourceCoordinator: SourceCoordinator
    @ObservedObject var reminderPreferencesController: ReminderPreferencesController
    /// 弹层倒计时依赖这个展示时钟每秒 tick，否则 SwiftUI 只会在
    /// `sourceCoordinator.state` 真正改变时才重绘，导致秒数长时间不动。
    @ObservedObject var menuBarPresentationClock: MenuBarPresentationClock
    let openSettingsAction: () -> Void

    var body: some View {
        ZStack {
            GlassBackdrop()

            VStack(alignment: .leading, spacing: 12) {
                headerRow
                heroCard
                actionList
            }
            .padding(12)
        }
        .frame(width: 324)
        .animation(GlassMotion.page, value: heroAnimationKey)
    }

    /// 顶部行保留“会议 + 刷新 + 主操作”三个层级。
    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.72))

                Image(systemName: statusSymbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .contentTransition(.opacity)

                Text(headerSubtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 8)

            Button {
                Task {
                    await sourceCoordinator.refresh(trigger: .manualRefresh)
                }
            } label: {
                Image(systemName: sourceCoordinator.state.isRefreshing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(sourceCoordinator.state.isRefreshing ? 180 : 0))
                    .contentTransition(.opacity)
            }
            .buttonStyle(GlassIconButtonStyle(cornerRadius: 11))
            .disabled(sourceCoordinator.state.isRefreshing)
            .glassQuietFocus()
            .animation(.smooth(duration: 0.24), value: sourceCoordinator.state.isRefreshing)

            Button {
                performPrimaryAction(primaryAction)
            } label: {
                Text(primaryAction.title)
                    .lineLimit(1)
            }
            .buttonStyle(GlassPillButtonStyle(tone: .primary))
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    /// 中央主卡负责承载最重要的状态。
    /// 有会议时优先显示大号倒计时，没有会议时切成状态说明卡。
    @ViewBuilder
    private var heroCard: some View {
        GlassCard(cornerRadius: 20, padding: 0, tintOpacity: 0.28) {
            VStack(alignment: .leading, spacing: 10) {
                Group {
                    if let countdownValue = heroCountdownValue {
                        Text(countdownValue)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(heroCountdownColor)
                            .monospacedDigit()
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    } else {
                        Text(heroHeadline)
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(2)
                            .foregroundStyle(Color.primary.opacity(0.94))
                            .contentTransition(.opacity)
                    }
                }
                .id(heroPrimaryAnimationKey)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))

                VStack(alignment: .leading, spacing: 6) {
                    Text(heroSupportingTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                        .contentTransition(.opacity)

                    Text(heroSupportingSubtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .contentTransition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .frame(minHeight: 132, alignment: .topLeading)
        }
        .animation(GlassMotion.page, value: heroPrimaryAnimationKey)
    }

    /// 底部动作区改成轻量菜单列表，而不是三个同权重的大按钮。
    /// 这样主视觉焦点会停留在中间的提醒信息，而不是底部命令。
    @ViewBuilder
    private var actionList: some View {
        GlassPanel(cornerRadius: 20, padding: 0, overlayOpacity: 0.12) {
            VStack(spacing: 0) {
                actionRow(
                    title: localized("打开日历", "Open Calendar"),
                    symbolName: "calendar",
                    trailing: sourceCoordinator.state.nextMeeting != nil ? "✓" : nil,
                    tint: .primary,
                    action: openCalendarApp
                )

                divider

                actionRow(
                    title: localized("偏好设置…", "Preferences..."),
                    symbolName: "gearshape",
                    tint: .primary,
                    action: openSettingsWindow
                )

                divider

                actionRow(
                    title: localized("退出倒计时", "Quit Countdown"),
                    symbolName: "xmark.circle",
                    tint: .red,
                    action: {
                        NSApplication.shared.terminate(nil)
                    }
                )
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }

    private func actionRow(
        title: String,
        symbolName: String,
        trailing: String? = nil,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.9))
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)

                Spacer()

                if let trailing {
                    Text(trailing)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(GlassListRowButtonStyle())
        .glassQuietFocus()
    }

    private var headerTitle: String {
        if let nextMeeting = sourceCoordinator.state.nextMeeting {
            return nextMeeting.title
        }

        switch sourceCoordinator.state.healthState {
        case .ready:
            return localized("会议倒计时", "Meeting Countdown")
        case .unconfigured:
            return localized("需要完成配置", "Setup Required")
        case .warning:
            return localized("同步需要关注", "Sync Needs Attention")
        case .failed:
            return localized("无法读取会议", "Unable to Read Meetings")
        }
    }

    private var headerSubtitle: String {
        if sourceCoordinator.state.isRefreshing {
            return localized("正在刷新日历…", "Refreshing calendars...")
        }

        if let nextMeeting = sourceCoordinator.state.nextMeeting {
            return nextMeeting.source.displayName
        }

        if let lastErrorMessage = sourceCoordinator.state.lastErrorMessage {
            return lastErrorMessage
        }

        return localizedHealthStateSummary
    }

    private var statusSymbolName: String {
        if sourceCoordinator.state.nextMeeting != nil {
            return "calendar"
        }

        return sourceCoordinator.state.healthState.symbolName
    }

    private var heroHeadline: String {
        switch sourceCoordinator.state.healthState {
        case .ready:
            return localized("当前没有即将开始的会议", "No upcoming meeting")
        case .unconfigured:
            return localized("先完成日历接入", "Complete calendar setup")
        case .warning:
            return localized("检查本地日历同步", "Check local calendar sync")
        case .failed:
            return localized("会议读取失败", "Meeting read failed")
        }
    }

    /// 主卡只有在会议已经接近时才显示 `MM:SS`，
    /// 远于一小时则退回成标题型状态卡，避免面板长期像秒表一样吵闹。
    private var heroCountdownValue: String? {
        guard let nextMeeting = sourceCoordinator.state.nextMeeting else {
            return nil
        }

        let interval = nextMeeting.startAt.timeIntervalSince(menuBarPresentationClock.now)
        guard interval <= 60 * 60 else {
            return nil
        }

        let remainingSeconds = max(0, Int(ceil(interval)))
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 只有进入最后 20 秒才把主卡倒计时切成红色强调态；
    /// 再早的时段保持与副标题一致的白色，避免整块面板长期发红带来的焦虑感。
    private var heroCountdownColor: Color {
        if let nextMeeting = sourceCoordinator.state.nextMeeting,
           nextMeeting.startAt.timeIntervalSince(menuBarPresentationClock.now) <= 20 {
            return .red
        }

        return .white
    }

    private var heroSupportingTitle: String {
        if let nextMeeting = sourceCoordinator.state.nextMeeting {
            let interval = nextMeeting.startAt.timeIntervalSince(menuBarPresentationClock.now)
            if interval <= 0 {
                return localized("会议已开始", "Meeting started")
            }
            let formattedTime = Self.heroTimeFormatter.string(from: nextMeeting.startAt)
            return localized("开始时间 \(formattedTime)", "Starts at \(formattedTime)")
        }

        return primaryAction.subtitleFallback
    }

    private var heroSupportingSubtitle: String {
        if let nextMeeting = sourceCoordinator.state.nextMeeting {
            var parts = [nextMeeting.source.displayName]
            if nextMeeting.hasVideoConferenceLink {
                parts.append(localized("视频会议已就绪", "Video Ready"))
            }
            return parts.joined(separator: " · ")
        }

        if let lastErrorMessage = sourceCoordinator.state.lastErrorMessage {
            return lastErrorMessage
        }

        return localizedHealthStateSummary
    }

    /// 让主卡在“倒计时模式”和“状态说明模式”之间切换时有稳定的动画锚点。
    private var heroPrimaryAnimationKey: String {
        heroCountdownValue ?? heroHeadline
    }

    /// 把主卡和顶部标题当前可见内容压成一个 token，便于统一驱动过渡动画。
    private var heroAnimationKey: String {
        [
            heroPrimaryAnimationKey,
            heroSupportingTitle,
            heroSupportingSubtitle,
            headerTitle,
            headerSubtitle,
            sourceCoordinator.state.isRefreshing ? "refreshing" : "idle"
        ].joined(separator: "|")
    }

    /// 主按钮继续沿用现有业务决策：
    /// 有链接时优先直达，无链接时回到系统日历，没有会议时进入恢复或配置动作。
    private var primaryAction: PrimaryAction {
        if let nextMeeting = sourceCoordinator.state.nextMeeting {
            if let preferredLink = preferredMeetingLink(for: nextMeeting) {
                return PrimaryAction(
                    title: preferredLink.kind == .videoConference ? localized("加入会议", "Join Video") : localized("查看详情", "View Details"),
                    subtitleFallback: localized("打开下一场会议", "Open the next meeting"),
                    handler: {
                        NSWorkspace.shared.open(preferredLink.url)
                    }
                )
            }

            return PrimaryAction(
                title: localized("打开日历", "Open Calendar"),
                subtitleFallback: localized("查看已同步事件", "Inspect the synced event"),
                handler: openCalendarApp
            )
        }

        switch sourceCoordinator.state.healthState {
        case .unconfigured:
            return PrimaryAction(
                title: localized("完成配置", "Complete Setup"),
                subtitleFallback: localized("授予权限并选择日历", "Grant access and select calendars"),
                handler: openSettingsWindow
            )
        case .warning:
            return PrimaryAction(
                title: localized("重新检查同步", "Re-check Sync"),
                subtitleFallback: localized("刷新本地日历状态", "Refresh the local calendar state"),
                handler: {
                    Task {
                        await sourceCoordinator.refresh(trigger: .manualRefresh)
                    }
                }
            )
        case .failed, .ready:
            return PrimaryAction(
                title: localized("打开日历", "Open Calendar"),
                subtitleFallback: localized("检查本地日历源", "Inspect the local calendar source"),
                handler: openCalendarApp
            )
        }
    }

    private func preferredMeetingLink(for meeting: MeetingRecord) -> MeetingLink? {
        if let videoLink = meeting.links.first(where: { $0.kind == .videoConference }) {
            return videoLink
        }

        if let detailLink = meeting.links.first(where: { $0.kind == .eventDetail }) {
            return detailLink
        }

        return meeting.links.first
    }

    private func performPrimaryAction(_ action: PrimaryAction) {
        action.handler()
    }

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

    private func openSettingsWindow() {
        openSettingsAction()
    }

    private var uiLanguage: AppUILanguage {
        reminderPreferencesController.reminderPreferences.interfaceLanguage
    }

    private var localizedHealthStateSummary: String {
        switch sourceCoordinator.state.healthState {
        case .unconfigured:
            return localized("接入尚未完成。请先授权并选择目标日历。", "Setup is incomplete. Grant access and choose a calendar first.")
        case .ready:
            return localized("本地日历读取正常。", "The local calendar source is healthy.")
        case .warning:
            return localized("本地日历同步仍可使用，但需要关注同步状态。", "The local calendar source is still usable, but its sync state needs attention.")
        case .failed:
            return sourceCoordinator.state.lastErrorMessage
                ?? localized("当前无法正常读取会议。", "The app cannot read meetings right now.")
        }
    }

    private func localized(_ chinese: String, _ english: String) -> String {
        uiLanguage == .english ? english : chinese
    }

    private static let heroTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct PrimaryAction {
    let title: String
    let subtitleFallback: String
    let handler: () -> Void
}
