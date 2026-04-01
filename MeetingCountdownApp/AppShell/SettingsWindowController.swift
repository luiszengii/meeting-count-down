import AppKit
import SwiftUI

/// `SettingsWindowController` 专门记录 SwiftUI `Settings` scene 背后的那一扇真实 `NSWindow`。
/// 菜单栏应用不能自己重造设置窗口，否则会偏离 SwiftUI 官方支持的打开方式；
/// 这里的职责只是等设置页真正挂到窗口上之后，缓存窗口引用并把它提到前台。
@MainActor
final class SettingsWindowController {
    /// 这里必须是弱引用，避免控制器反过来强持有窗口，打乱 AppKit 的窗口生命周期。
    private weak var settingsWindow: NSWindow?
    /// 当用户显式要求打开设置，但窗口还没真正创建出来时，先记住这次前置请求。
    /// 等 SwiftUI 设置场景把真实 `NSWindow` 注册进来后，只消费一次这次请求。
    private var shouldActivateOnNextRegistration = false

    /// 当设置页解析出自己所在的 `NSWindow` 后，把它登记到控制器里，供菜单栏入口复用。
    func register(window: NSWindow) {
        settingsWindow = window

        guard shouldActivateOnNextRegistration else {
            return
        }

        shouldActivateOnNextRegistration = false
        activateKnownWindow()
    }

    /// 用户显式要求打开设置窗口时统一走这里。
    /// 如果窗口已经存在，就立刻前置；如果窗口还没准备好，就把这次前置请求挂起到下一次注册。
    func requestWindowActivation() {
        guard settingsWindow != nil else {
            shouldActivateOnNextRegistration = true
            return
        }

        shouldActivateOnNextRegistration = false
        activateKnownWindow()
    }

    /// 把已经存在的设置窗口拉到最前面。
    /// 这一步只负责“已有窗口的前台化”，不负责创建窗口，因此可以安全配合 `openSettings()` 使用。
    func activateKnownWindow() {
        guard let settingsWindow else {
            return
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow.orderFrontRegardless()
        settingsWindow.makeKeyAndOrderFront(nil)
    }
}

/// `SettingsWindowAccessor` 借助一个极轻量的 `NSViewRepresentable` 拿到宿主 `NSWindow`。
/// SwiftUI 视图默认拿不到窗口对象，所以需要插入一个 AppKit 子视图，再在下一轮主线程里读取 `view.window`。
struct SettingsWindowAccessor: NSViewRepresentable {
    /// 解析到窗口后的回调由设置页提供，便于把窗口登记到共享控制器中。
    let onResolveWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        resolveWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        resolveWindow(for: nsView)
    }

    /// `view.window` 在 `makeNSView` 当下通常还是 `nil`，因此需要推迟到下一轮主线程再读取。
    private func resolveWindow(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }

            onResolveWindow(window)
        }
    }
}
