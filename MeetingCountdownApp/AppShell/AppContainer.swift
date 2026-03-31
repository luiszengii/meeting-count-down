import Foundation

/// `AppContainer` 是 Phase 0 的依赖装配入口。
/// 现在产品已经收敛成 CalDAV 单一路径，因此这里直接组装真实的系统日历桥接能力，
/// 不再为其他接入方式预留占位数据源。
enum AppContainer {
    /// 构造整个 App 的运行期依赖集合。
    /// 系统日历桥接需要共享 EventKit bridge、偏好存储和变化监听生命周期，
    /// 因此比起在视图层分散创建对象，更适合先统一装进一个 runtime 容器。
    @MainActor
    static func makeAppRuntime() -> AppRuntime {
        let dateProvider = SystemDateProvider()
        let preferencesStore = UserDefaultsPreferencesStore()
        let calendarAccess = EventKitSystemCalendarAccess()
        let settingsWindowController = SettingsWindowController()
        let systemCalendarSource = SystemCalendarMeetingSource(
            calendarAccess: calendarAccess,
            preferencesStore: preferencesStore
        )

        let sourceCoordinator = SourceCoordinator(
            source: systemCalendarSource,
            nextMeetingSelector: DefaultNextMeetingSelector(),
            dateProvider: dateProvider,
            logger: AppLogger(source: "SourceCoordinator"),
            autoRefreshOnStart: true
        )

        let systemCalendarConnectionController = SystemCalendarConnectionController(
            calendarAccess: calendarAccess,
            preferencesStore: preferencesStore,
            dateProvider: dateProvider,
            onCalendarConfigurationChanged: { [weak sourceCoordinator] trigger in
                await sourceCoordinator?.refresh(trigger: trigger)
            },
            autoRefreshOnStart: true
        )

        return AppRuntime(
            sourceCoordinator: sourceCoordinator,
            systemCalendarConnectionController: systemCalendarConnectionController,
            settingsWindowController: settingsWindowController
        )
    }
}
