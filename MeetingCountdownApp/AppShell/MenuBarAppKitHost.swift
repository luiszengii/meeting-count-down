import AppKit
import SwiftUI

/// `MenuBarAppKitHost` 是 `NSStatusItem` / `NSStatusBarButton` / `NSPopover` 的唯一管理者。
/// 它只负责 AppKit 对象的生命周期和外观应用，不持有任何业务状态，也不推导任何 presentation 规则。
///
/// ## 设计原则
/// - 单一职责：只做"presentation 值 → AppKit 控件状态"的翻译，不持有 ReminderEngine/SourceCoordinator。
/// - 所有 NSColor / NSFont / 胶囊背景 / 宽度数学都集中在这里，方便统一审查和调整。
/// - `installIfNeeded()` 和 `apply(presentation:)` 是唯二对外暴露的核心动作。
@MainActor
final class MenuBarAppKitHost {

    /// 胶囊提醒态需要显式限制最大宽度，避免长标题把状态栏按钮撑得过宽后出现奇怪的垂直挤压。
    private static let maxCapsuleStatusItemLength: CGFloat = GlassUITheme.MenuBar.maxCapsuleStatusItemLength
    /// 菜单弹层当前由固定尺寸的控制面板承载。
    private static let popoverContentSize = GlassUITheme.MenuBar.popoverContentSize

    /// AppKit 菜单栏按钮本体。
    private var statusItem: NSStatusItem?
    /// 点击菜单栏按钮后展示的浮层。
    private let popover: NSPopover
    /// 避免重复安装同一个状态栏项。
    private var hasInstalledStatusItem = false

    /// 用于配置弹层内容的闭包，在 `installIfNeeded()` 时调用。
    private let popoverContentProvider: () -> NSViewController
    /// 用于响应按钮点击的 toggle 动作由外部注入，保持宿主层无业务依赖。
    private let onButtonAction: () -> Void

    /// - Parameters:
    ///   - popoverContentProvider: 返回弹层根视图控制器的工厂闭包，仅在安装时调用一次。
    ///   - onButtonAction: 每次点击菜单栏按钮时的回调，由 `MenuBarStatusItemController` 提供。
    init(
        popoverContentProvider: @escaping () -> NSViewController,
        onButtonAction: @escaping () -> Void
    ) {
        self.popoverContentProvider = popoverContentProvider
        self.onButtonAction = onButtonAction

        self.popover = NSPopover()
        self.popover.behavior = .transient
        self.popover.animates = true
        self.popover.appearance = NSAppearance(named: .vibrantLight)
    }

    // MARK: - Public API

    /// 在 app 完成启动后安装真正的菜单栏入口。
    /// 把"构造对象"和"把 AppKit 控件挂到系统菜单栏"两个阶段分开，
    /// 避免在过早的生命周期里操作状态栏。
    func installIfNeeded() {
        guard !hasInstalledStatusItem else {
            return
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        configureStatusItemButton(statusItem.button)
        configurePopover()
        hasInstalledStatusItem = true
    }

    /// 把纯值 presentation 翻译成 AppKit 按钮的外观状态。
    /// 这里不重新推导任何业务规则，只消费已经聚合好的 presentation。
    func apply(presentation: MenuBarPresentation) {
        guard hasInstalledStatusItem, let statusItem, let button = statusItem.button else {
            return
        }

        let foregroundColor = resolvedForegroundColor(for: presentation)
        let backgroundColor = resolvedBackgroundColor(for: presentation)
        let titleWeight = resolvedTitleWeight(for: presentation)

        applyStatusItemTitle(
            to: button,
            for: presentation.title,
            color: foregroundColor,
            weight: titleWeight
        )
        button.image = configuredSymbolImage(
            named: presentation.symbolName,
            weight: titleWeight,
            accessibilityLabel: presentation.title
        )
        /// 不设置 `contentTintColor` 时，template symbol 会交回系统菜单栏统一渲染。
        /// 这对深色菜单栏、副屏灰态和未来系统外观变化都更稳；只有红色提醒态需要我们显式指定白色。
        button.contentTintColor = foregroundColor
        button.imagePosition = .imageLeading
        button.toolTip = presentation.title

        /// `NSStatusItem.variableLength` 只会按当前内容的紧凑宽度收缩。
        /// 胶囊背景需要额外左右留白，因此这里主动给状态栏项补一点宽度。
        let extraWidth: CGFloat = presentation.showsCapsuleBackground ? GlassUITheme.MenuBar.extraWidth : 0
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

    /// 展开或关闭弹出的状态面板。
    func togglePopover() {
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
    func dismissPopover() {
        closePopover()
    }

    // MARK: - Private helpers

    private func closePopover() {
        popover.performClose(nil)
    }

    /// 按钮本身继续走 AppKit target/action，而外观改由我们自己控制。
    private func configureStatusItemButton(_ button: NSStatusBarButton?) {
        guard let button else {
            return
        }

        button.target = self
        button.action = #selector(handleButtonAction(_:))
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .imageLeading
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.masksToBounds = true
        button.cell?.wraps = false
        button.cell?.lineBreakMode = .byTruncatingTail
    }

    @objc
    private func handleButtonAction(_ sender: AnyObject?) {
        onButtonAction()
    }

    /// 浮层内容由外部注入的工厂闭包提供，保持宿主层无业务依赖。
    private func configurePopover() {
        let contentViewController = popoverContentProvider()
        contentViewController.view.frame = NSRect(origin: .zero, size: Self.popoverContentSize)
        popover.contentViewController = contentViewController
        popover.contentSize = Self.popoverContentSize
    }

    // MARK: - Appearance resolution

    /// 菜单栏图标和文字默认交给系统渲染，才能在深色菜单栏和副屏灰态下跟其他状态栏 app 保持一致。
    /// 只有红色闪烁态有自定义背景色，因此需要显式把前景色压成白色。
    private func resolvedForegroundColor(for presentation: MenuBarPresentation) -> NSColor? {
        if presentation.shouldHighlightRed {
            return .white
        }

        return nil
    }

    /// 会前预热态允许稍微加重，但真正的高优先级提醒仍然最重。
    private func resolvedTitleWeight(for presentation: MenuBarPresentation) -> NSFont.Weight {
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
    private func resolvedBackgroundColor(for presentation: MenuBarPresentation) -> NSColor {
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

    /// 普通态用 `button.title + button.font`，让 AppKit 自己决定菜单栏前景色。
    /// 如果走 `attributedTitle` 并显式写入 `.labelColor`，副屏菜单栏和深色菜单栏就可能失去系统的自动白色/灰色模板渲染。
    private func applyStatusItemTitle(
        to button: NSStatusBarButton,
        for title: String,
        color: NSColor?,
        weight: NSFont.Weight
    ) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: weight)
        guard let color else {
            button.font = font
            button.title = title
            return
        }

        button.attributedTitle = statusItemTitle(
            for: title,
            color: color,
            font: font
        )
    }

    /// 给显式前景色的状态栏标题补上单行截断样式，避免长标题在系统压缩布局时尝试换行。
    private func statusItemTitle(
        for title: String,
        color: NSColor,
        font: NSFont
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail

        return NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
        )
    }
}
