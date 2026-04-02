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

    /// 会议读取状态仍然来自唯一的协调层。
    private let sourceCoordinator: SourceCoordinator
    /// 提醒命中态和倒计时秒数仍然只认提醒引擎的聚合状态。
    private let reminderEngine: ReminderEngine
    /// 设置窗口前台化仍然通过共享控制器统一完成。
    private let settingsWindowController: SettingsWindowController
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

    init(
        sourceCoordinator: SourceCoordinator,
        reminderEngine: ReminderEngine,
        settingsWindowController: SettingsWindowController,
        menuBarPresentationClock: MenuBarPresentationClock
    ) {
        self.sourceCoordinator = sourceCoordinator
        self.reminderEngine = reminderEngine
        self.settingsWindowController = settingsWindowController
        self.menuBarPresentationClock = menuBarPresentationClock
        self.popover = NSPopover()
        self.popover.behavior = .transient
        self.popover.animates = true

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

    /// 浮层里的内容仍然复用 SwiftUI 视图，只是改成显式注入“打开设置”动作，
    /// 避免继续依赖 `MenuBarExtra` 独有的环境值。
    private func configurePopover() {
        let rootView = MenuBarContentView(
            sourceCoordinator: sourceCoordinator,
            reminderEngine: reminderEngine,
            openSettingsAction: { [weak self] in
                self?.openSettingsWindow()
            }
        )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 280)
        hostingController.view.layoutSubtreeIfNeeded()
        popover.contentViewController = hostingController
        popover.contentSize = hostingController.view.fittingSize
    }

    /// 设置窗口仍然由 SwiftUI `Settings` scene 真正创建。
    /// 这里的职责只是触发官方动作，并尽量把已经存在的窗口提到最前面。
    private func openSettingsWindow() {
        closePopover()
        settingsWindowController.requestWindowActivation()
        NSApplication.shared.activate(ignoringOtherApps: true)

        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) == false {
            _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
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
    }

    /// 把纯值 presentation 转成 AppKit 按钮样式。
    /// 这里不重新推导业务规则，只消费已经聚合好的菜单栏 presentation。
    private func updateStatusItemAppearance() {
        guard hasInstalledStatusItem, let statusItem, let button = statusItem.button else {
            return
        }

        let presentation = currentPresentation(at: menuBarPresentationClock.now)
        let foregroundColor = presentation.shouldHighlightRed ? NSColor.white : NSColor.labelColor
        let backgroundColor = resolvedBackgroundColor(for: presentation)
        let titleWeight: NSFont.Weight = presentation.isHighPriority ? .bold : .semibold

        button.attributedTitle = statusItemTitle(
            for: presentation.title,
            color: foregroundColor,
            weight: titleWeight
        )
        button.image = configuredSymbolImage(
            named: presentation.symbolName,
            weight: presentation.isHighPriority ? .bold : .semibold,
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
    private func currentPresentation(at now: Date) -> ReminderMenuBarAlertPresentation {
        reminderEngine.state.menuBarAlertPresentation(at: now) ?? ReminderMenuBarAlertPresentation(
            title: sourceCoordinator.menuBarTitle,
            symbolName: sourceCoordinator.menuBarSymbolName,
            isHighPriority: false,
            showsCapsuleBackground: false,
            shouldHighlightRed: false
        )
    }

    /// AppKit 只需要一个最终颜色值，不关心这个颜色来自普通态还是红色闪烁态。
    private func resolvedBackgroundColor(for presentation: ReminderMenuBarAlertPresentation) -> NSColor {
        guard presentation.showsCapsuleBackground else {
            return .clear
        }

        if presentation.shouldHighlightRed {
            return .systemRed
        }

        return .labelColor.withAlphaComponent(0.16)
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
