import EventKit
import Foundation

/// `SystemCalendarConnectionController` 负责承载 CalDAV / 系统日历路线的配置状态。
/// 它的职责是把“授权访问日历”“枚举候选日历”“保存多选结果”“监听系统日历变化”这些动作
/// 从 SwiftUI 视图里抽出来，并在动作完成后统一触发会议源刷新。
@MainActor
final class SystemCalendarConnectionController: ObservableObject {
    /// 当前系统日历授权状态。
    @Published private(set) var authorizationState: SystemCalendarAuthorizationState
    /// 当前机器上可见的事件日历候选。
    @Published private(set) var availableCalendars: [SystemCalendarDescriptor]
    /// 当前已选中的系统日历 ID 集合。
    @Published private(set) var selectedCalendarIDs: Set<String>
    /// 当前是否正在重新读取系统日历状态。
    @Published private(set) var isLoadingState: Bool
    /// 当前是否正在等待系统权限框返回。
    @Published private(set) var isRequestingAccess: Bool
    /// 最近一次状态刷新时间。
    @Published private(set) var lastLoadedAt: Date?
    /// 最近一次可读错误。
    @Published private(set) var lastErrorMessage: String?

    /// EventKit 桥接层。
    private let calendarAccess: any SystemCalendarAccessing
    /// 非敏感配置持久化入口。
    private let preferencesStore: any PreferencesStore
    /// 独立注入时钟，便于测试。
    private let dateProvider: any DateProviding
    /// 用于监听系统日历变化的通知中心。
    private let notificationCenter: NotificationCenter
    /// 当配置或系统日历内容发生变化后，应统一通知 app 壳层刷新。
    private let onCalendarConfigurationChanged: @MainActor @Sendable (RefreshTrigger) async -> Void
    /// `EKEventStoreChanged` 监听 token。
    private var eventStoreChangedObserver: NSObjectProtocol?

    init(
        calendarAccess: any SystemCalendarAccessing,
        preferencesStore: any PreferencesStore,
        dateProvider: any DateProviding,
        notificationCenter: NotificationCenter = .default,
        onCalendarConfigurationChanged: @escaping @MainActor @Sendable (RefreshTrigger) async -> Void = { _ in },
        autoRefreshOnStart: Bool = true
    ) {
        self.calendarAccess = calendarAccess
        self.preferencesStore = preferencesStore
        self.dateProvider = dateProvider
        self.notificationCenter = notificationCenter
        self.onCalendarConfigurationChanged = onCalendarConfigurationChanged
        self.authorizationState = calendarAccess.currentAuthorizationState()
        self.availableCalendars = []
        self.selectedCalendarIDs = []
        self.isLoadingState = false
        self.isRequestingAccess = false
        self.lastLoadedAt = nil
        self.lastErrorMessage = nil

        registerEventStoreChangedObserver()

        if autoRefreshOnStart {
            Task { [weak self] in
                await self?.refreshState()
            }
        }
    }

    /// 重新同步“权限 -> 候选日历 -> 已选日历”的整份状态。
    /// 设置页首次打开、用户点刷新、权限变化或系统日历变化后都走这里。
    func refreshState() async {
        isLoadingState = true
        lastErrorMessage = nil

        defer {
            isLoadingState = false
        }

        authorizationState = calendarAccess.currentAuthorizationState()

        guard authorizationState.allowsReading else {
            availableCalendars = []
            selectedCalendarIDs = []
            lastLoadedAt = dateProvider.now()
            return
        }

        let calendars = calendarAccess.fetchCalendars()
        var storedSelectedIDs = await preferencesStore.loadSelectedSystemCalendarIDs()
        let hasStoredSelection = await preferencesStore.hasStoredSelectedSystemCalendarIDs()
        let availableCalendarIDs = Set(calendars.map(\.id))
        storedSelectedIDs = storedSelectedIDs.intersection(availableCalendarIDs)

        if storedSelectedIDs.isEmpty && !hasStoredSelection {
            let suggestedIDs = Set(calendars.filter(\.isSuggestedByDefault).map(\.id))

            if !suggestedIDs.isEmpty {
                storedSelectedIDs = suggestedIDs
                try? await preferencesStore.saveSelectedSystemCalendarIDs(suggestedIDs)
            }
        } else {
            try? await preferencesStore.saveSelectedSystemCalendarIDs(storedSelectedIDs)
        }

        availableCalendars = calendars
        selectedCalendarIDs = storedSelectedIDs
        lastLoadedAt = dateProvider.now()
    }

    /// 用户显式点击按钮后才触发 EventKit 权限申请。
    func requestCalendarAccess() async {
        isRequestingAccess = true
        lastErrorMessage = nil

        defer {
            isRequestingAccess = false
        }

        do {
            authorizationState = try await calendarAccess.requestReadAccess()
            await refreshState()
            await onCalendarConfigurationChanged(.manualRefresh)
        } catch {
            lastErrorMessage = error.localizedDescription
            authorizationState = calendarAccess.currentAuthorizationState()
            await onCalendarConfigurationChanged(.manualRefresh)
        }
    }

    /// 切换某个候选系统日历的选择状态并立即持久化。
    func setCalendarSelection(calendarID: String, isSelected: Bool) async {
        var updatedSelection = selectedCalendarIDs

        if isSelected {
            updatedSelection.insert(calendarID)
        } else {
            updatedSelection.remove(calendarID)
        }

        selectedCalendarIDs = updatedSelection
        try? await preferencesStore.saveSelectedSystemCalendarIDs(updatedSelection)
        await onCalendarConfigurationChanged(.manualRefresh)
    }

    /// 当前是否已经至少选中一条系统日历。
    var hasSelectedCalendars: Bool {
        !selectedCalendarIDs.isEmpty
    }

    /// 给设置页显示当前已选条数。
    var selectionSummary: String {
        hasSelectedCalendars ? "已选 \(selectedCalendarIDs.count) 个日历" : "尚未选择系统日历"
    }

    /// 当系统 Calendar 内容发生变化时，先重载候选列表，再统一通知 app 刷新当前数据源。
    private func handleEventStoreChangedNotification() async {
        await refreshState()
        await onCalendarConfigurationChanged(.systemCalendarChanged)
    }

    /// 统一注册 EventKit 变化监听。
    private func registerEventStoreChangedObserver() {
        eventStoreChangedObserver = notificationCenter.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleEventStoreChangedNotification()
            }
        }
    }
}
