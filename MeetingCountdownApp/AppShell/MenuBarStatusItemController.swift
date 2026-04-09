import AppKit
import Combine
import SwiftUI

/// `MenuBarStatusItemController` 用 AppKit 的 `NSStatusItem` 托管真正的菜单栏按钮。
/// 这样我们既能继续复用 SwiftUI 写的弹出内容，又能直接控制按钮的背景层、
/// 字体和颜色，绕开 `MenuBarExtra` 对复杂标签样式的宿主限制。
@MainActor
final class MenuBarStatusItemController {
    /// 胶囊提醒态需要显式限制最大宽度，避免长标题把状态栏按钮撑得过宽后出现奇怪的垂直挤压。
    private static let maxCapsuleStatusItemLength: CGFloat = 220
    /// 菜单弹层当前由固定尺寸的控制面板承载。
    /// 这里显式记录尺寸，避免安装 `NSHostingController` 时为了取 `fittingSize`
    /// 强行触发布局，进而撞上 AppKit 的递归布局警告。
    private static let popoverContentSize = NSSize(width: 324, height: 270)

    /// 会议读取状态仍然来自唯一的协调层。
    private let sourceCoordinator: SourceCoordinator
    /// 提醒命中态和倒计时秒数仍然只认提醒引擎的聚合状态。
    private let reminderEngine: ReminderEngine
    /// 当前界面语言跟随偏好控制器变化，菜单栏按钮和弹层都要一起刷新。
    private let reminderPreferencesController: ReminderPreferencesController
    /// 设置窗口现在由共享控制器手动创建和前台化。
    private let settingsWindowController: SettingsWindowController
    /// 打开设置动作仍然走统一桥接器，方便菜单栏和 app 菜单共用同一条打开链路。
    private let settingsSceneOpenController: SettingsSceneOpenController
    /// 秒级倒计时和闪烁节奏继续共用现有展示时钟。
    private let menuBarPresentationClock: MenuBarPresentationClock

    /// AppKit 菜单栏按钮本体。
    private var statusItem: NSStatusItem?
    /// 点击菜单栏按钮后展示的浮层。
    private let popover: NSPopover
    /// 监听多个状态源后统一刷新按钮外观。
    private var cancellables: Set<AnyCancellable> = []
    /// 避免重复安装同一个状态栏项。
    private var hasInstalledStatusItem = false

    /// 菜单栏静态展示至少需要区分三种体验层级：
    /// `idle` 只是安静待命，`meetingSoon` 开始强调即将到来的会议，
    /// `urgent` 则由提醒引擎驱动进入真正的高优先级态。
    private enum StatusItemVisualState {
        case idle
        case meetingSoon
        case urgent
    }

    /// AppKit 真正消费的是这一层更靠近绘制的数据。
    /// 它把领域层的提醒 presentation 再折成“应该怎样看起来”这一层，
    /// 方便在不污染 ReminderEngine 的前提下收紧菜单栏三态视觉。
    private struct StatusItemPresentation {
        let title: String
        let symbolName: String
        let visualState: StatusItemVisualState
        let isHighPriority: Bool
        let showsCapsuleBackground: Bool
        let shouldHighlightRed: Bool
    }

    init(
        sourceCoordinator: SourceCoordinator,
        reminderEngine: ReminderEngine,
        reminderPreferencesController: ReminderPreferencesController,
        settingsWindowController: SettingsWindowController,
        settingsSceneOpenController: SettingsSceneOpenController,
        menuBarPresentationClock: MenuBarPresentationClock
    ) {
        self.sourceCoordinator = sourceCoordinator
        self.reminderEngine = reminderEngine
        self.reminderPreferencesController = reminderPreferencesController
        self.settingsWindowController = settingsWindowController
        self.settingsSceneOpenController = settingsSceneOpenController
        self.menuBarPresentationClock = menuBarPresentationClock
        self.popover = NSPopover()
        self.popover.behavior = .transient
        self.popover.animates = true
        self.popover.appearance = NSAppearance(named: .vibrantLight)

        bindPresentationUpdates()
    }

    /// 在 app 完成启动后安装真正的菜单栏入口。
    /// 之所以显式分成 `installIfNeeded()`，是为了把“构造对象”和“把 AppKit 控件挂到系统菜单栏”
    /// 两个阶段分开，避免在过早的生命周期里操作状态栏。
    func installIfNeeded() {
        guard !hasInstalledStatusItem else {
            return
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        configureStatusItemButton(statusItem.button)
        configurePopover()
        hasInstalledStatusItem = true
        updateStatusItemAppearance()
    }

    /// 菜单栏按钮只有一个交互职责：展开或关闭弹出的状态面板。
    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else {
            return
        }

        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    /// 外部动作（如打开设置）需要先把当前浮层关闭，避免两层界面同时悬在前台。
    private func closePopover() {
        popover.performClose(nil)
    }

    /// 按钮本身继续走 AppKit target/action，而外观改由我们自己控制。
    private func configureStatusItemButton(_ button: NSStatusBarButton?) {
        guard let button else {
            return
        }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .imageLeading
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.masksToBounds = true
        button.cell?.wraps = false
        button.cell?.lineBreakMode = .byTruncatingTail
    }

    /// 浮层里的内容仍然复用 SwiftUI 视图，只是现在不再需要依赖 SwiftUI 环境里的
    /// `openSettings` 动作；菜单栏只拿一个显式注入的打开设置闭包即可。
    private func configurePopover() {
        let rootView = MenuBarContentView(
            sourceCoordinator: sourceCoordinator,
            reminderPreferencesController: reminderPreferencesController,
            openSettingsAction: { [weak self] in
                self?.openSettingsWindow()
            }
        )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.frame = NSRect(origin: .zero, size: Self.popoverContentSize)
        popover.contentViewController = hostingController
        popover.contentSize = Self.popoverContentSize
    }

    /// 菜单栏入口只负责触发统一的设置窗口打开动作；
    /// 真正的窗口创建和单例复用都交给 `SettingsWindowController`。
    private func openSettingsWindow() {
        closePopover()
        NSApplication.shared.activate(ignoringOtherApps: true)

        if !settingsSceneOpenController.openSettingsIfAvailable() {
            settingsWindowController.requestWindowActivation()
        }
    }

    /// 统一监听三类会影响菜单栏按钮展示的状态：
    /// 会议读取结果、提醒状态和展示时钟。
    private func bindPresentationUpdates() {
        Publishers.CombineLatest3(
            sourceCoordinator.$state,
            reminderEngine.$state,
            menuBarPresentationClock.$now
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _ in
            self?.updateStatusItemAppearance()
        }
        .store(in: &cancellables)

        reminderPreferencesController.$reminderPreferences
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)
    }

    /// 把纯值 presentation 转成 AppKit 按钮样式。
    /// 这里不重新推导业务规则，只消费已经聚合好的菜单栏 presentation。
    private func updateStatusItemAppearance() {
        guard hasInstalledStatusItem, let statusItem, let button = statusItem.button else {
            return
        }

        let presentation = currentPresentation(at: menuBarPresentationClock.now)
        let foregroundColor = resolvedForegroundColor(for: presentation)
        let backgroundColor = resolvedBackgroundColor(for: presentation)
        let titleWeight = resolvedTitleWeight(for: presentation)

        button.attributedTitle = statusItemTitle(
            for: presentation.title,
            color: foregroundColor,
            weight: titleWeight
        )
        button.image = configuredSymbolImage(
            named: presentation.symbolName,
            weight: titleWeight,
            accessibilityLabel: presentation.title
        )
        button.contentTintColor = foregroundColor
        button.imagePosition = .imageLeading
        button.toolTip = presentation.title

        /// `NSStatusItem.variableLength` 只会按当前内容的紧凑宽度收缩。
        /// 胶囊背景需要额外左右留白，因此这里主动给状态栏项补一点宽度。
        let extraWidth: CGFloat = presentation.showsCapsuleBackground ? 12 : 0
        let idealLength = max(NSStatusItem.squareLength, button.fittingSize.width + extraWidth)
        statusItem.length = presentation.showsCapsuleBackground
            ? min(Self.maxCapsuleStatusItemLength, idealLength)
            : idealLength

        button.layer?.backgroundColor = backgroundColor.cgColor
        button.layer?.cornerRadius = presentation.showsCapsuleBackground
            ? max(0, (NSStatusBar.system.thickness - 4) / 2)
            : 0
        button.layer?.masksToBounds = presentation.showsCapsuleBackground
    }

    /// 如果提醒引擎当前没有高优先级 presentation，就退回到协调层原有的普通菜单栏标题。
    private func currentPresentation(at now: Date) -> StatusItemPresentation {
        if let alertPresentation = localizedAlertPresentation(at: now) {
            return StatusItemPresentation(
                title: alertPresentation.title,
                symbolName: alertPresentation.symbolName,
                visualState: .urgent,
                isHighPriority: alertPresentation.isHighPriority,
                showsCapsuleBackground: alertPresentation.showsCapsuleBackground,
                shouldHighlightRed: alertPresentation.shouldHighlightRed
            )
        }

        if let nextMeeting = sourceCoordinator.state.nextMeeting,
           nextMeeting.startAt.timeIntervalSince(now) <= 30 * 60 {
            return StatusItemPresentation(
                title: localizedMenuBarTitle(at: now),
                symbolName: sourceCoordinator.menuBarSymbolName,
                visualState: .meetingSoon,
                isHighPriority: false,
                showsCapsuleBackground: true,
                shouldHighlightRed: false
            )
        }

        return StatusItemPresentation(
            title: localizedMenuBarTitle(at: now),
            symbolName: sourceCoordinator.menuBarSymbolName,
            visualState: .idle,
            isHighPriority: false,
            showsCapsuleBackground: false,
            shouldHighlightRed: false
        )
    }

    private var uiLanguage: AppUILanguage {
        reminderPreferencesController.reminderPreferences.interfaceLanguage
    }

    /// 状态栏普通态优先显示倒计时，否则回退到本地化后的短健康标签。
    private func localizedMenuBarTitle(at now: Date) -> String {
        if let nextMeeting = sourceCoordinator.state.nextMeeting {
            return localizedCountdownLine(until: nextMeeting.startAt, now: now)
        }

        switch sourceCoordinator.state.healthState {
        case .unconfigured:
            return localized("未配置", "Setup")
        case .ready:
            return localized("就绪", "Ready")
        case .warning:
            return localized("注意", "Warn")
        case .failed:
            return localized("失败", "Failed")
        }
    }

    /// 提醒命中态如果继续直接走领域层默认 presentation，会把中文标题带回状态栏。
    /// 这里在壳层按同样的状态机规则重新组装一份跟随界面语言的 presentation。
    private func localizedAlertPresentation(at now: Date) -> ReminderMenuBarAlertPresentation? {
        switch reminderEngine.state {
        case let .playing(context, _):
            let remainingInterval = context.meeting.startAt.timeIntervalSince(now)

            if remainingInterval > 0 {
                let remainingSeconds = max(1, Int(ceil(remainingInterval)))
                return ReminderMenuBarAlertPresentation(
                    title: "\(remainingSeconds)s",
                    symbolName: "timer.circle.fill",
                    isHighPriority: true,
                    showsCapsuleBackground: true,
                    shouldHighlightRed: shouldHighlightCountdownRed(at: now, remainingSeconds: remainingSeconds)
                )
            }

            return ReminderMenuBarAlertPresentation(
                title: context.meeting.title,
                symbolName: "exclamationmark.circle.fill",
                isHighPriority: true,
                showsCapsuleBackground: true,
                shouldHighlightRed: false
            )

        case let .triggeredSilently(_, _, reason):
            switch reason {
            case .userMuted:
                return ReminderMenuBarAlertPresentation(
                    title: localized("静音开会", "Muted"),
                    symbolName: "bell.slash.circle.fill",
                    isHighPriority: true,
                    showsCapsuleBackground: true,
                    shouldHighlightRed: false
                )
            case .outputRoutePolicy:
                return ReminderMenuBarAlertPresentation(
                    title: localized("避免外放", "Private Audio"),
                    symbolName: "speaker.slash.circle.fill",
                    isHighPriority: true,
                    showsCapsuleBackground: true,
                    shouldHighlightRed: false
                )
            }

        case .idle, .scheduled, .disabled, .failed:
            return nil
        }
    }

    private func localizedCountdownLine(until date: Date, now: Date) -> String {
        let interval = max(0, date.timeIntervalSince(now))

        if interval < 60 {
            return localized("即将开始", "Soon")
        }

        let totalSeconds = Int(interval.rounded(.up))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if uiLanguage == .english {
            if hours > 0 {
                return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
            }

            return "\(max(1, minutes))m"
        }

        if hours > 0 {
            return minutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes) 分钟"
        }

        return "\(max(1, minutes)) 分钟"
    }

    private func shouldHighlightCountdownRed(at now: Date, remainingSeconds: Int) -> Bool {
        guard remainingSeconds <= 10 else {
            return false
        }

        let period: TimeInterval = remainingSeconds <= 4 ? 0.5 : 1.0
        let remainder = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        return remainder < period / 2
    }

    private func localized(_ chinese: String, _ english: String) -> String {
        uiLanguage == .english ? english : chinese
    }

    /// 菜单栏 quiet / soon / urgent 三态会切不同的前景色策略。
    private func resolvedForegroundColor(for presentation: StatusItemPresentation) -> NSColor {
        if presentation.shouldHighlightRed {
            return .white
        }

        switch presentation.visualState {
        case .idle:
            return .labelColor
        case .meetingSoon:
            return .controlAccentColor
        case .urgent:
            return .labelColor
        }
    }

    /// 会前预热态允许稍微加重，但真正的高优先级提醒仍然最重。
    private func resolvedTitleWeight(for presentation: StatusItemPresentation) -> NSFont.Weight {
        switch presentation.visualState {
        case .idle:
            return .semibold
        case .meetingSoon:
            return .bold
        case .urgent:
            return presentation.isHighPriority ? .bold : .semibold
        }
    }

    /// AppKit 只需要一个最终颜色值，不关心这个颜色来自普通态还是红色闪烁态。
    private func resolvedBackgroundColor(for presentation: StatusItemPresentation) -> NSColor {
        guard presentation.showsCapsuleBackground else {
            return .clear
        }

        if presentation.shouldHighlightRed {
            return .systemRed
        }

        switch presentation.visualState {
        case .idle:
            return .clear
        case .meetingSoon:
            return .controlAccentColor.withAlphaComponent(0.16)
        case .urgent:
            return .labelColor.withAlphaComponent(0.16)
        }
    }

    /// SF Symbol 图标仍然沿用系统模板图标，让 `contentTintColor` 统一控制前景色。
    private func configuredSymbolImage(
        named symbolName: String,
        weight: NSFont.Weight,
        accessibilityLabel: String
    ) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: weight)
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityLabel
        )?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    /// 给状态栏标题补上显式的单行截断样式，避免长标题在系统压缩布局时尝试换行。
    private func statusItemTitle(
        for title: String,
        color: NSColor,
        weight: NSFont.Weight
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail

        return NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: weight),
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
        )
    }
}
