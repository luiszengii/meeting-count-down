import Foundation

/// `AppContainer` 是当前 app 的依赖装配入口。
/// 现在产品已经收敛成 CalDAV 单一路径，因此这里直接组装真实的系统日历桥接、
/// 提醒调度和默认音效能力，不再为其他接入方式预留占位数据源。
enum AppContainer {
    /// 构造整个 App 的运行期依赖集合。
    /// 系统日历桥接、提醒调度和窗口控制器都需要共享生命周期，
    /// 所以比起在视图层分散创建对象，更适合先统一装进一个 runtime 容器。
    @MainActor
    static func makeAppRuntime() -> AppRuntime {
        let dateProvider = SystemDateProvider()
        let preferencesStore = UserDefaultsPreferencesStore()
        let calendarAccess = EventKitSystemCalendarAccess()
        let settingsWindowController = SettingsWindowController()
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

        let sourceCoordinator = SourceCoordinator(
            source: systemCalendarSource,
            nextMeetingSelector: DefaultNextMeetingSelector(),
            preferencesStore: preferencesStore,
            dateProvider: dateProvider,
            logger: AppLogger(source: "SourceCoordinator"),
            lastSuccessfulRefreshAt: UserDefaultsPreferencesStore.bootstrapLastSuccessfulRefreshAt(),
            autoRefreshOnStart: true
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
            onCalendarConfigurationChanged: { [weak sourceCoordinator] trigger in
                await sourceCoordinator?.refresh(trigger: trigger)
            },
            autoRefreshOnStart: true
        )

        let reminderPreferencesController = ReminderPreferencesController(
            preferencesStore: preferencesStore,
            onPreferencesChanged: { [weak sourceCoordinator] in
                await sourceCoordinator?.refresh(trigger: .preferencesChanged)
            },
            autoRefreshOnStart: true
        )

        let soundProfileLibraryController = SoundProfileLibraryController(
            preferencesStore: preferencesStore,
            assetStore: soundProfileAssetStore,
            previewPlayer: soundProfilePreviewPlayer,
            onSelectedSoundProfileChanged: { [weak sourceCoordinator] in
                await sourceCoordinator?.refresh(trigger: .preferencesChanged)
            },
            autoRefreshOnStart: true
        )

        let launchAtLoginController = LaunchAtLoginController()
        let menuBarPresentationClock = MenuBarPresentationClock()
        let menuBarStatusItemController = MenuBarStatusItemController(
            sourceCoordinator: sourceCoordinator,
            reminderEngine: reminderEngine,
            settingsWindowController: settingsWindowController,
            menuBarPresentationClock: menuBarPresentationClock
        )
        let appRefreshController = AppRefreshController(
            sourceCoordinator: sourceCoordinator,
            dateProvider: dateProvider
        )

        return AppRuntime(
            sourceCoordinator: sourceCoordinator,
            systemCalendarConnectionController: systemCalendarConnectionController,
            reminderEngine: reminderEngine,
            reminderPreferencesController: reminderPreferencesController,
            soundProfileLibraryController: soundProfileLibraryController,
            launchAtLoginController: launchAtLoginController,
            settingsWindowController: settingsWindowController,
            menuBarPresentationClock: menuBarPresentationClock,
            menuBarStatusItemController: menuBarStatusItemController,
            appRefreshController: appRefreshController
        )
    }
}
