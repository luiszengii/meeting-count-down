import AppKit
import SwiftUI

/// `SettingsWindowController` 专门记录 SwiftUI `Settings` scene 背后的那一扇真实 `NSWindow`。
/// 之前这里依赖系统 `Settings` scene 提供真实窗口，但那条链路仍然会把窗口行为锁成
/// 系统偏好样式，导致我们后续追加的 `.resizable` 和最小尺寸约束无法真正生效。
/// 现在控制器改为自己创建并持有一扇 `NSWindow`，这样菜单栏应用就能稳定得到
/// 一扇可前置、可缩放、可复用的设置窗口。
@MainActor
final class SettingsWindowController {
    /// 设置窗口允许收缩到的最小内容尺寸。
    /// 这里的宽高会和 SwiftUI 根视图的最小尺寸保持一致，避免一边允许缩小、一边布局已经塌陷。
    private static let minimumWindowSize = NSSize(width: 680, height: 540)
    /// 首次创建设置窗口时使用的默认内容尺寸。
    /// 这个值刻意略大于最小尺寸，让响应式卡片布局在第一次打开时就有舒展空间。
    private static let defaultWindowSize = NSSize(width: 920, height: 700)

    /// 手动创建的设置窗口需要由控制器自己强持有，否则关闭后会被提前释放。
    private var settingsWindow: NSWindow?
    /// 设置页 SwiftUI 根视图由壳层装配阶段提供，控制器只负责在真正需要时懒创建窗口。
    private var makeRootView: (() -> AnyView)?

    /// 壳层装配完成后，把设置页根视图的构造闭包登记进来。
    /// 这里不提前创建窗口，避免菜单栏 app 一启动就弹出设置页。
    func configureWindowContent<Content: View>(
        @ViewBuilder _ content: @escaping () -> Content
    ) {
        makeRootView = { AnyView(content()) }
    }

    /// 用户显式要求打开设置窗口时统一走这里。
    /// 如果窗口还没创建，就先按当前登记的 SwiftUI 内容懒创建一扇，再统一前置。
    func requestWindowActivation() {
        guard let settingsWindow = ensureWindow() else {
            return
        }

        activate(window: settingsWindow)
    }

    /// 把已经存在的设置窗口拉到最前面。
    /// 这一步只负责“已有窗口的前台化”，不负责创建窗口，因此可以安全配合 `openSettings()` 使用。
    func activateKnownWindow() {
        guard let settingsWindow else {
            return
        }

        activate(window: settingsWindow)
    }

    /// 如果窗口还不存在，就用当前登记的根视图真正创建一扇。
    /// 这样菜单栏和 app 菜单都不需要关心窗口生命周期细节，只要请求打开即可。
    private func ensureWindow() -> NSWindow? {
        if let settingsWindow {
            return settingsWindow
        }

        guard let makeRootView else {
            return nil
        }

        let hostingController = NSHostingController(rootView: makeRootView())
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.setContentSize(Self.defaultWindowSize)
        window.center()
        configureAppearance(for: window)
        settingsWindow = window
        return window
    }

    /// 前置手动窗口时统一走同一条路径，避免后续不同入口各自设置一套激活顺序。
    private func activate(window: NSWindow) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    /// 设置窗口本身也需要更接近参考图里的半透明浮层。
    /// 这里统一把 titlebar 透明化，并允许窗口背景透出内容视图自己的玻璃底板。
    private func configureAppearance(for window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.toolbarStyle = .unifiedCompact
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.contentMinSize = Self.minimumWindowSize
        window.setFrameAutosaveName("MeetingCountdown.SettingsWindow")
    }
}
