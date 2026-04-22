import AppKit
import Combine
import SwiftUI

/// `MenuBarStatusItemController` 是菜单栏的编排层。
/// 它监听三类状态源，通过 `MenuBarPresentationCalculator` 计算出纯值 presentation，
/// 再把结果交给 `MenuBarAppKitHost` 完成实际的 AppKit 渲染。
///
/// ## 职责边界（重构后）
/// - 持有 calculator、host 和 Combine 订阅；
/// - 把 `Publishers.CombineLatest3` 管线接到 calculator → host 的数据流上；
/// - 不包含任何 presentation 计算逻辑，不直接操作 NSStatusItem / NSPopover。
@MainActor
final class MenuBarStatusItemController {

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

    /// AppKit 控件宿主：负责 NSStatusItem / NSStatusBarButton / NSPopover 的生命周期和外观应用。
    private lazy var host: MenuBarAppKitHost = makeHost()
    /// 监听多个状态源后统一刷新按钮外观。
    private var cancellables: Set<AnyCancellable> = []

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

        bindPresentationUpdates()
    }

    // MARK: - Public API

    /// 在 app 完成启动后安装真正的菜单栏入口。
    func installIfNeeded() {
        host.installIfNeeded()
        applyCurrentPresentation()
    }

    // MARK: - Private

    /// 延迟构造 host，确保 self 已完整初始化后再捕获 weak 引用。
    private func makeHost() -> MenuBarAppKitHost {
        MenuBarAppKitHost(
            popoverContentProvider: { [weak self] in
                guard let self else {
                    return NSViewController()
                }

                let rootView = MenuBarContentView(
                    sourceCoordinator: self.sourceCoordinator,
                    reminderPreferencesController: self.reminderPreferencesController,
                    openSettingsAction: { [weak self] in
                        self?.openSettingsWindow()
                    }
                )
                let hostingController = NSHostingController(rootView: rootView)
                hostingController.view.frame = NSRect(
                    origin: .zero,
                    size: GlassUITheme.MenuBar.popoverContentSize
                )
                return hostingController
            },
            onButtonAction: { [weak self] in
                self?.host.togglePopover()
            }
        )
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
            self?.applyCurrentPresentation()
        }
        .store(in: &cancellables)

        reminderPreferencesController.$reminderPreferences
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyCurrentPresentation()
            }
            .store(in: &cancellables)
    }

    /// 计算当前 presentation 并让 host 渲染。
    private func applyCurrentPresentation() {
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: reminderEngine.state,
            sourceCoordinatorState: sourceCoordinator.state,
            now: menuBarPresentationClock.now,
            uiLanguage: reminderPreferencesController.reminderPreferences.interfaceLanguage
        )
        host.apply(presentation: presentation)
    }

    /// 菜单栏入口只负责触发统一的设置窗口打开动作；
    /// 真正的窗口创建和单例复用都交给 `SettingsWindowController`。
    private func openSettingsWindow() {
        host.dismissPopover()
        NSApplication.shared.activate(ignoringOtherApps: true)

        if !settingsSceneOpenController.openSettingsIfAvailable() {
            settingsWindowController.requestWindowActivation()
        }
    }
}
