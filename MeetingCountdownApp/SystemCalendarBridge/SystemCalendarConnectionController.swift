import EventKit
import Foundation

/// `SystemCalendarConnectionController` 负责承载 CalDAV / 系统日历路线的配置状态。
/// 它的职责是把"授权访问日历""枚举候选日历""保存多选结果""监听系统日历变化"这些动作
/// 从 SwiftUI 视图里抽出来，并在动作完成后统一触发会议源刷新。
///
/// 遵从 `AsyncStateController`：
/// - `loadingState` 对应原 `isLoadingState`（重新读取系统日历状态时的忙碌标志）。
/// - `isRequestingAccess` 保留为独立属性（等待系统权限框返回的忙碌标志），
///   语义上属于独立的 OS 权限申请操作，不应合并进 `loadingState`。
/// - `errorMessage` 对应原 `lastErrorMessage`。
/// - 对外保留 `refreshState()` 入口（供视图层、内部通知回调等调用），
///   其实现委托给 `AsyncStateController.refresh()` 协议默认实现。
@MainActor
final class SystemCalendarConnectionController: ObservableObject, AsyncStateController {
    /// 当前系统日历授权状态。
    @Published private(set) var authorizationState: SystemCalendarAuthorizationState
    /// 当前机器上可见的事件日历候选。
    @Published private(set) var availableCalendars: [SystemCalendarDescriptor]
    /// 最近一次从持久化里读到的原始日历选择。
    /// 这里故意保留"原样读取"结果，方便区分"用户曾经选过，但现在这些 ID 已经失效"。
    @Published private(set) var lastLoadedStoredCalendarIDs: Set<String>
    /// 最近一次原始持久化选择里，当前系统里已经不存在的日历 ID。
    @Published private(set) var lastUnavailableStoredCalendarIDs: Set<String>
    /// 当前已选中的系统日历 ID 集合。
    @Published private(set) var selectedCalendarIDs: Set<String>
    /// 当前是否已经至少有过一次显式保存的系统日历选择。
    @Published private(set) var hasStoredSelection: Bool
    /// 当前是否正在重新读取系统日历状态。（AsyncStateController.loadingState）
    @Published var loadingState: Bool
    /// 当前是否正在等待系统权限框返回。
    @Published private(set) var isRequestingAccess: Bool
    /// 当前日历勾选结果的自动保存反馈状态。
    @Published private(set) var selectionPersistenceState: CalendarSelectionPersistenceState
    /// 最近一次状态刷新时间。
    @Published private(set) var lastLoadedAt: Date?
    /// 最近一次可读错误。（AsyncStateController.errorMessage）
    @Published var errorMessage: String?

    /// EventKit 桥接层。
    private let calendarAccess: any SystemCalendarAccessing
    /// 非敏感配置持久化入口。
    private let preferencesStore: any PreferencesStore
    /// 独立注入时钟，便于测试。
    private let dateProvider: any DateProviding
    /// 统一的连接状态日志入口。
    private let logger: AppLogger
    /// 用于监听系统日历变化的通知中心。
    private let notificationCenter: NotificationCenter
    /// 当配置或系统日历内容发生变化后，应统一通知 app 壳层刷新。
    private let onCalendarConfigurationChanged: @MainActor @Sendable (RefreshTrigger) async -> Void
    /// `EKEventStoreChanged` 监听 token。
    private var eventStoreChangedObserver: NSObjectProtocol?
    /// "已保存"提示需要自动消失，因此控制器自己持有一个可取消任务。
    private var selectionPersistenceResetTask: Task<Void, Never>?

    init(
        calendarAccess: any SystemCalendarAccessing,
        preferencesStore: any PreferencesStore,
        dateProvider: any DateProviding,
        logger: AppLogger = AppLogger(source: "SystemCalendarConnection"),
        notificationCenter: NotificationCenter = .default,
        onCalendarConfigurationChanged: @escaping @MainActor @Sendable (RefreshTrigger) async -> Void = { _ in },
        autoRefreshOnStart: Bool = true
    ) {
        self.calendarAccess = calendarAccess
        self.preferencesStore = preferencesStore
        self.dateProvider = dateProvider
        self.logger = logger
        self.notificationCenter = notificationCenter
        self.onCalendarConfigurationChanged = onCalendarConfigurationChanged
        self.authorizationState = calendarAccess.currentAuthorizationState()
        self.availableCalendars = []
        self.lastLoadedStoredCalendarIDs = []
        self.lastUnavailableStoredCalendarIDs = []
        self.selectedCalendarIDs = []
        self.hasStoredSelection = false
        self.loadingState = false
        self.isRequestingAccess = false
        self.selectionPersistenceState = .idle
        self.lastLoadedAt = nil
        self.errorMessage = nil

        registerEventStoreChangedObserver()

        if autoRefreshOnStart {
            Task { [weak self] in
                await self?.refresh()
            }
        }
    }

    /// 重新同步"权限 -> 候选日历 -> 已选日历"的整份状态。
    /// 设置页首次打开、用户点刷新、权限变化或系统日历变化后都走这里。
    /// 委托给 `AsyncStateController.refresh()` 协议默认实现以保证 `loadingState` 统一管理。
    func refreshState() async {
        await refresh()
    }

    /// 真正的日历状态加载逻辑（`AsyncStateController.performRefresh` 的实现）。
    /// 由 `refresh()` 协议默认实现负责包裹 `loadingState` 切换和异常捕获。
    func performRefresh() async throws {
        logger.info("Refreshing system calendar connection state")

        authorizationState = calendarAccess.currentAuthorizationState()

        guard authorizationState.allowsReading else {
            availableCalendars = []
            selectedCalendarIDs = []
            selectionPersistenceState = .idle
            lastLoadedAt = dateProvider.now()
            logger.info("System calendar connection stopped at authorization state \(authorizationState.badgeText)")
            return
        }

        let calendars = calendarAccess.fetchCalendars()
        var storedSelectedIDs = await preferencesStore.loadSelectedSystemCalendarIDs()
        let hasStoredSelection = await preferencesStore.hasStoredSelectedSystemCalendarIDs()
        let availableCalendarIDs = Set(calendars.map(\.id))
        let unavailableStoredCalendarIDs = storedSelectedIDs.subtracting(availableCalendarIDs)
        lastLoadedStoredCalendarIDs = storedSelectedIDs
        lastUnavailableStoredCalendarIDs = unavailableStoredCalendarIDs
        self.hasStoredSelection = hasStoredSelection

        storedSelectedIDs = storedSelectedIDs.intersection(availableCalendarIDs)

        if storedSelectedIDs.isEmpty && !hasStoredSelection {
            let suggestedIDs = Set(calendars.filter(\.isSuggestedByDefault).map(\.id))

            if !suggestedIDs.isEmpty {
                storedSelectedIDs = suggestedIDs
                do {
                    try await preferencesStore.saveSelectedSystemCalendarIDs(suggestedIDs)
                    self.hasStoredSelection = true
                    logger.info("Auto-selected \(suggestedIDs.count) suggested system calendars on first authorized load")
                } catch {
                    // 故意保持 hasStoredSelection = false，让下次启动可以重新尝试自动选择。
                    logger.error("Failed to persist auto-selected calendar IDs: \(error.localizedDescription)")
                }
            }
        } else {
            do {
                try await preferencesStore.saveSelectedSystemCalendarIDs(storedSelectedIDs)
            } catch {
                logger.error("Failed to persist reconciled system calendar IDs: \(error.localizedDescription)")
            }
        }

        availableCalendars = calendars
        selectedCalendarIDs = storedSelectedIDs
        selectionPersistenceState = .idle
        lastLoadedAt = dateProvider.now()
        logger.info(
            "System calendar connection state ready: available=\(calendars.count), stored=\(lastLoadedStoredCalendarIDs.count), unavailableStored=\(lastUnavailableStoredCalendarIDs.count), effectiveSelected=\(selectedCalendarIDs.count)"
        )
    }

    /// 用户显式点击按钮后才触发 EventKit 权限申请。
    func requestCalendarAccess() async {
        logger.info("Requesting system calendar access from user action")
        isRequestingAccess = true
        errorMessage = nil

        defer {
            isRequestingAccess = false
        }

        do {
            authorizationState = try await calendarAccess.requestReadAccess()
            await refresh()
            await onCalendarConfigurationChanged(.manualRefresh)
            logger.info("Calendar access request completed with state \(authorizationState.badgeText)")
        } catch {
            errorMessage = error.localizedDescription
            authorizationState = calendarAccess.currentAuthorizationState()
            await onCalendarConfigurationChanged(.manualRefresh)
            logger.error("Calendar access request failed: \(error.localizedDescription)")
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

        await persistCalendarSelection(updatedSelection)
    }

    /// 批量覆盖当前选中的系统日历集合。
    /// "全选 / 清空"会直接走这里，和单项勾选共享同一套自动保存反馈与失败回滚规则。
    func setSelectedCalendarIDs(_ calendarIDs: Set<String>) async {
        await persistCalendarSelection(calendarIDs)
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
        await refresh()
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

    /// 统一处理日历选择的乐观更新、持久化、成功提示和失败回滚。
    private func persistCalendarSelection(_ updatedSelection: Set<String>) async {
        let previousSelection = selectedCalendarIDs
        let previousStoredSelection = lastLoadedStoredCalendarIDs
        let previousUnavailableSelection = lastUnavailableStoredCalendarIDs
        let previousHasStoredSelection = hasStoredSelection

        guard updatedSelection != previousSelection
            || previousStoredSelection != updatedSelection
            || !previousHasStoredSelection else {
            return
        }

        cancelSelectionPersistenceResetTask()
        selectionPersistenceState = .saving
        selectedCalendarIDs = updatedSelection
        lastLoadedStoredCalendarIDs = updatedSelection
        lastUnavailableStoredCalendarIDs = []
        hasStoredSelection = true

        do {
            try await preferencesStore.saveSelectedSystemCalendarIDs(updatedSelection)
            selectionPersistenceState = .saved
            await onCalendarConfigurationChanged(.manualRefresh)
            scheduleSelectionPersistenceReset()
            logger.info("Updated system calendar selection to \(updatedSelection.count) calendar(s)")
        } catch {
            selectedCalendarIDs = previousSelection
            lastLoadedStoredCalendarIDs = previousStoredSelection
            lastUnavailableStoredCalendarIDs = previousUnavailableSelection
            hasStoredSelection = previousHasStoredSelection
            selectionPersistenceState = .failed(message: "未能更新日历选择，已恢复到上一次保存状态")
            logger.error("Failed to persist system calendar selection: \(error.localizedDescription)")
        }
    }

    /// "已保存"提示是短暂反馈，过一小段时间后回到空闲态即可。
    private func scheduleSelectionPersistenceReset() {
        selectionPersistenceResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            guard let self, self.selectionPersistenceState == .saved else {
                return
            }

            self.selectionPersistenceState = .idle
            self.selectionPersistenceResetTask = nil
        }
    }

    /// 新的保存动作开始前，要先取消前一个"自动清空提示"任务，避免旧任务把新状态抹掉。
    private func cancelSelectionPersistenceResetTask() {
        selectionPersistenceResetTask?.cancel()
        selectionPersistenceResetTask = nil
    }
}
