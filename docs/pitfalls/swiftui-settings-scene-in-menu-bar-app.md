# swiftui-settings-scene-in-menu-bar-app

## 现象

- 菜单栏里的“打开设置”能把设置页打开，但设置窗口经常落在别的应用窗口后面。
- 如果为了强行置前而改用 `showSettingsWindow:`，运行时会报出 `Please use SettingsLink for opening the Settings scene.`。
- 当菜单栏入口已经切到 `NSStatusItem + NSPopover` 后，这个问题会再次以回归形式出现：AppKit 控制器拿不到 SwiftUI 的 `openSettings` 环境值，于是很容易又退回到旧 selector。

## 背景

当前 app 是 `LSUIElement` 菜单栏应用，设置页由 SwiftUI `Settings` scene 托管，不是手写的普通 `NSWindowController`。这意味着“打开设置”和“把窗口置前”虽然看起来像同一件事，实际上分别受 SwiftUI scene 生命周期和 AppKit 窗口层级控制。

## 排查过程

1. 最开始直接使用 `SettingsLink`，功能上能打开设置页，但窗口焦点和层级不稳定。
2. 为了把窗口拉到最前，尝试走 `NSApplication.sendAction(Selector(("showSettingsWindow:")), ...)`。
3. 运行时立刻收到系统告警，说明 SwiftUI `Settings` scene 不应该再被 AppKit 的旧 action 直接驱动。
4. 进一步确认：真正需要补的是“窗口置前”和“把 SwiftUI 官方动作桥接给 AppKit 壳层”，不是“绕过 SwiftUI 重新发起一次打开动作”。
5. 第一轮修复是把设置页里的真实 `NSWindow` 解析出来，交给共享控制器缓存和前置。
6. 后续菜单栏入口改成 `NSStatusItem + NSPopover` 后，再次出现回归；最终又补了一层 [SettingsSceneOpenController.swift](../../MeetingCountdownApp/AppShell/SettingsSceneOpenController.swift)，由弹层里的 SwiftUI 视图在渲染时登记 `openSettings` 动作，再让 AppKit 壳层复用。

## 根因

根因不是设置页无法打开，而是：

1. `Settings` scene 的正确打开方式属于 SwiftUI 自己的 scene API，不应直接混用 `showSettingsWindow:`。
2. `LSUIElement` 菜单栏 app 在激活自身和展示设置窗口时，窗口层级比普通前台 app 更容易出现“窗口存在，但没到最前”的问题。
3. 当设置入口位于 `NSStatusItem` / `NSPopover` 这类 AppKit 壳层里时，AppKit 控制器并不能直接访问 SwiftUI 场景环境，所以“继续走官方 scene API”需要额外桥接，而不是偷懒退回旧 selector。

## 解决方案

1. 菜单入口继续使用 SwiftUI 官方支持的 `openSettings()`，不要直接调用 `showSettingsWindow:`。
2. 新增 [SettingsWindowController.swift](../../MeetingCountdownApp/AppShell/SettingsWindowController.swift)，专门缓存已经创建出来的设置窗口。
3. 在 [SettingsView.swift](../../MeetingCountdownApp/AppShell/SettingsView.swift) 里插入 `SettingsWindowAccessor`，等 `view.window` 可用后登记窗口并执行 `activate(ignoringOtherApps:)`、`orderFrontRegardless()`、`makeKeyAndOrderFront(nil)`。
4. 对于 `NSStatusItem + NSPopover` 菜单栏壳层，再新增 [SettingsSceneOpenController.swift](../../MeetingCountdownApp/AppShell/SettingsSceneOpenController.swift) 和 [MenuBarContentView.swift](../../MeetingCountdownApp/AppShell/MenuBarContentView.swift) 里的零尺寸注册视图，让 SwiftUI 弹层把 `openSettings` 环境动作登记给 AppKit 控制器。

## 预防方式

- 未来只要还是 SwiftUI `Settings` scene，就不要再回退到 `showSettingsWindow:` 这类旧式 AppKit 入口。
- 不要再靠窗口标题模糊匹配去猜哪一扇是设置窗口；优先从设置页自身拿到真实 `NSWindow`。
- 如果设置入口位于 AppKit 宿主里，先想清楚“官方 SwiftUI 动作怎么桥接过去”，而不是直接写 selector fallback。
- 手工验收时把“别的 app 在前台时点击菜单栏打开设置”单独列为一个场景，不要只测设置页能否出现。

## 相关链接

- 开发日志：[2026-03-31](../dev-logs/2026-03-31.md)
- 开发日志：[2026-04-02](../dev-logs/2026-04-02.md)
- ADR：[2026-03-30 Phase 1 先用设置窗口承载接入向导](../adrs/2026-03-30-onboarding-routes-through-settings-window.md)
- 相关目录 `AGENTS.md`：[AppShell](../../MeetingCountdownApp/AppShell/AGENTS.md)
