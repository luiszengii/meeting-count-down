import Foundation
import SwiftUI

/// `AppContainer` 是当前 app 的依赖装配入口。
/// 现在产品已经收敛成 CalDAV 单一路径，因此这里直接组装真实的系统日历桥接、
/// 提醒调度和默认音效能力，不再为其他接入方式预留占位数据源。
enum AppContainer {
    /// 构造整个 App 的运行期依赖集合。
    /// 系统日历桥接、提醒调度和窗口控制器都需要共享生命周期，
    /// 所以比起在视图层分散创建对象，更适合先统一装进一个 runtime 容器。
    ///
    // MARK: - Startup error policy
    //
    // 截至当前版本，这个方法里的所有子组件构造器都是不可抛出的：
    //   - `UserDefaultsPreferencesStore` / `EventKitSystemCalendarAccess` /
    //     `SoundProfileAssetStore` / `CoreAudioOutputRouteProvider` 等系统桥接
    //     都把错误延迟到真正调用系统 API 时再抛，构造期间不会失败；
    //   - `SourceCoordinator` / `ReminderEngine` / 各 Controller 也只是把依赖
    //     存到属性里，没有任何 `try`。
    // 因此这里没有给签名加 `throws`，避免把不可能抛错的调用强行包成 do/catch
    // 噪声。FeishuMeetingCountdownApp 也按此假设直接持有 `AppRuntime`。
    //
    // 未来如果有任何子组件改为可抛错（例如音频引擎要做 `warmUp` 预检、偏好
    // 存储引入迁移逻辑、EventKit 改成同步申请授权），需要按下面的步骤接入：
    //   1. 把这个方法的签名改成 `static func makeAppRuntime() throws -> AppRuntime`；
    //   2. 在抛错点用 `do/catch` 包一层，按领域包装成
    //      `StartupError.audioEngineUnavailable(underlying:)` /
    //      `StartupError.preferencesStoreUnavailable(underlying:)` /
    //      `StartupError.unexpected(stage:underlying:)` 之一再 `throw`；
    //   3. 同步更新 `FeishuMeetingCountdownAppDelegate.appRuntime` 的初始化方式
    //      （改成 `Result<AppRuntime, StartupError>` 或类似可观察状态），并让
    //      `FeishuMeetingCountdownApp.body` 在失败分支里渲染中文回退视图，避免
    //      整个应用静默崩溃。
    @MainActor
    static func makeAppRuntime() -> AppRuntime {
        let dateProvider = SystemDateProvider()
        let preferencesStore = UserDefaultsPreferencesStore()
        let calendarAccess = EventKitSystemCalendarAccess()
        let settingsWindowController = SettingsWindowController()
        let settingsSceneOpenController = SettingsSceneOpenController()
        let soundProfileAssetStore = SoundProfileAssetStore()
        let audioEngine = SelectableSoundProfileReminderAudioEngine(
            preferencesStore: preferencesStore,
            assetStore: soundProfileAssetStore,
            fallbackEngine: GeneratedToneReminderAudioEngine()
        )
        let soundProfilePreviewPlayer = SoundProfilePreviewPlayer(assetStore: soundProfileAssetStore)
        let audioOutputRouteProvider = CoreAudioOutputRouteProvider()
        let systemCalendarSource = SystemCalendarMeetingSource(
            calendarAccess: calendarAccess,
            preferencesStore: preferencesStore
        )

        // 单例事件总线：由所有生产者控制器共享，SourceCoordinator 订阅以驱动刷新。
        // 这是 T6 引入的核心架构改变：把分散的闭包回调链替换成统一的 PassthroughSubject 总线。
        let refreshEventBus = RefreshEventBus()

        let sourceCoordinator = SourceCoordinator(
            source: systemCalendarSource,
            nextMeetingSelector: DefaultNextMeetingSelector(),
            preferencesStore: preferencesStore,
            dateProvider: dateProvider,
            logger: AppLogger(source: "SourceCoordinator"),
            lastSuccessfulRefreshAt: UserDefaultsPreferencesStore.bootstrapLastSuccessfulRefreshAt(),
            autoRefreshOnStart: true,
            refreshEventBus: refreshEventBus
        )

        let reminderEngine = ReminderEngine(
            preferencesStore: preferencesStore,
            audioEngine: audioEngine,
            audioOutputRouteProvider: audioOutputRouteProvider,
            scheduler: TaskReminderScheduler(),
            dateProvider: dateProvider,
            logger: AppLogger(source: "ReminderEngine")
        )
        reminderEngine.bind(to: sourceCoordinator)

        let systemCalendarConnectionController = SystemCalendarConnectionController(
            calendarAccess: calendarAccess,
            preferencesStore: preferencesStore,
            dateProvider: dateProvider,
            refreshEventBus: refreshEventBus,
            autoRefreshOnStart: true
        )

        let reminderPreferencesController = ReminderPreferencesController(
            preferencesStore: preferencesStore,
            refreshEventBus: refreshEventBus,
            autoRefreshOnStart: true
        )

        let soundProfileLibraryController = SoundProfileLibraryController(
            preferencesStore: preferencesStore,
            assetStore: soundProfileAssetStore,
            previewPlayer: soundProfilePreviewPlayer,
            refreshEventBus: refreshEventBus,
            autoRefreshOnStart: true
        )

        let launchAtLoginController = LaunchAtLoginController()
        settingsWindowController.configureWindowContent {
            SettingsView(
                sourceCoordinator: sourceCoordinator,
                systemCalendarConnectionController: systemCalendarConnectionController,
                reminderEngine: reminderEngine,
                reminderPreferencesController: reminderPreferencesController,
                soundProfileLibraryController: soundProfileLibraryController,
                launchAtLoginController: launchAtLoginController
            )
                .frame(minWidth: 680, minHeight: 540)
        }
        settingsSceneOpenController.register { [weak settingsWindowController] in
            settingsWindowController?.requestWindowActivation()
        }
        let menuBarPresentationClock = MenuBarPresentationClock()
        let menuBarStatusItemController = MenuBarStatusItemController(
            sourceCoordinator: sourceCoordinator,
            reminderEngine: reminderEngine,
            reminderPreferencesController: reminderPreferencesController,
            settingsWindowController: settingsWindowController,
            settingsSceneOpenController: settingsSceneOpenController,
            menuBarPresentationClock: menuBarPresentationClock
        )
        let appRefreshController = AppRefreshController(
            sourceCoordinator: sourceCoordinator,
            dateProvider: dateProvider
        )

        let core = CoreRuntime(
            sourceCoordinator: sourceCoordinator,
            systemCalendarConnectionController: systemCalendarConnectionController,
            reminderEngine: reminderEngine,
            reminderPreferencesController: reminderPreferencesController,
            soundProfileLibraryController: soundProfileLibraryController,
            menuBarPresentationClock: menuBarPresentationClock
        )
        let shell = ShellRuntime(
            launchAtLoginController: launchAtLoginController,
            settingsWindowController: settingsWindowController,
            menuBarStatusItemController: menuBarStatusItemController,
            appRefreshController: appRefreshController
        )

        return AppRuntime(core: core, shell: shell)
    }
}
