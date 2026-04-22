import Combine
import Foundation
import XCTest
@testable import FeishuMeetingCountdown

/// 这些测试验证 Phase 2 系统日历桥接层的关键规则是否稳定。
@MainActor
final class SystemCalendarBridgeTests: XCTestCase {
    /// 验证默认推荐规则只认飞书 CalDAV 账户，不会把其它 CalDAV / iCloud 来源也一起标成推荐。
    func testShouldSuggestCalendarOnlyForFeishuCalDAVSource() {
        XCTAssertTrue(EventKitSystemCalendarAccess.shouldSuggestCalendar(sourceTitle: "caldav.feishu.cn"))
        XCTAssertTrue(EventKitSystemCalendarAccess.shouldSuggestCalendar(sourceTitle: "  CalDAV.FEISHU.CN  "))
        XCTAssertFalse(EventKitSystemCalendarAccess.shouldSuggestCalendar(sourceTitle: "iCloud"))
        XCTAssertFalse(EventKitSystemCalendarAccess.shouldSuggestCalendar(sourceTitle: "caldav.icloud.com"))
    }

    /// 验证当用户首次授权后还没有手动选过日历时，控制器会自动预选建议日历并持久化。
    func testConnectionControllerAutoSelectsSuggestedCalendarsOnFirstAuthorizedLoad() async {
        let preferencesStore = InMemoryPreferencesStore()
        let access = StubSystemCalendarAccess(
            authorizationState: .authorized,
            calendars: [
                calendar(id: "feishu", title: "飞书日历", suggested: true),
                calendar(id: "personal", title: "个人", suggested: false)
            ]
        )
        let controller = SystemCalendarConnectionController(
            calendarAccess: access,
            preferencesStore: preferencesStore,
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            autoRefreshOnStart: false
        )

        await controller.refreshState()
        let storedCalendarIDs = await preferencesStore.loadSelectedSystemCalendarIDs()

        XCTAssertEqual(controller.selectedCalendarIDs, ["feishu"])
        XCTAssertEqual(storedCalendarIDs, ["feishu"])
    }

    /// 验证当用户已经显式保存过“空选择”后，控制器不会在下一次刷新时又自动把推荐日历选回来。
    func testConnectionControllerDoesNotReselectSuggestedCalendarsAfterExplicitEmptySelection() async {
        let preferencesStore = InMemoryPreferencesStore(
            selectedSystemCalendarIDs: [],
            hasStoredSelectedSystemCalendarIDs: true
        )
        let access = StubSystemCalendarAccess(
            authorizationState: .authorized,
            calendars: [
                calendar(id: "feishu", title: "飞书日历", suggested: true),
                calendar(id: "personal", title: "个人", suggested: false)
            ]
        )
        let controller = SystemCalendarConnectionController(
            calendarAccess: access,
            preferencesStore: preferencesStore,
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            autoRefreshOnStart: false
        )

        await controller.refreshState()

        XCTAssertEqual(controller.selectedCalendarIDs, [])
    }

    /// 验证当持久化里还留着旧日历 ID，但当前系统列表里已经没有这些日历时，
    /// 控制器会把“原始持久化值”和“当前不可用的旧选择”都保留下来，供诊断页导出。
    func testConnectionControllerTracksUnavailableStoredSelectionsForDiagnostics() async {
        let preferencesStore = InMemoryPreferencesStore(
            selectedSystemCalendarIDs: ["missing-calendar"],
            hasStoredSelectedSystemCalendarIDs: true
        )
        let access = StubSystemCalendarAccess(
            authorizationState: .authorized,
            calendars: [calendar(id: "feishu", title: "飞书日历", suggested: true)]
        )
        let controller = SystemCalendarConnectionController(
            calendarAccess: access,
            preferencesStore: preferencesStore,
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            autoRefreshOnStart: false
        )

        await controller.refreshState()

        XCTAssertEqual(controller.lastLoadedStoredCalendarIDs, ["missing-calendar"])
        XCTAssertEqual(controller.lastUnavailableStoredCalendarIDs, ["missing-calendar"])
        XCTAssertEqual(controller.selectedCalendarIDs, [])
        XCTAssertTrue(controller.hasStoredSelection)
    }

    /// 验证用户切换某个系统日历选择后，会立即写回持久化层。
    func testConnectionControllerPersistsSelectionChanges() async {
        let preferencesStore = InMemoryPreferencesStore(selectedSystemCalendarIDs: ["feishu"])
        let access = StubSystemCalendarAccess(
            authorizationState: .authorized,
            calendars: [
                calendar(id: "feishu", title: "飞书日历", suggested: true),
                calendar(id: "personal", title: "个人", suggested: false)
            ]
        )
        let controller = SystemCalendarConnectionController(
            calendarAccess: access,
            preferencesStore: preferencesStore,
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            autoRefreshOnStart: false
        )

        await controller.refreshState()
        await controller.setCalendarSelection(calendarID: "personal", isSelected: true)
        let storedCalendarIDs = await preferencesStore.loadSelectedSystemCalendarIDs()

        XCTAssertEqual(controller.selectedCalendarIDs, ["feishu", "personal"])
        XCTAssertEqual(storedCalendarIDs, ["feishu", "personal"])
    }

    /// 验证自动保存失败时，控制器会回滚到上一次成功保存的日历选择，
    /// 避免 UI 停在一个看似已生效、实际上没有写入持久化层的假状态。
    func testConnectionControllerRollsBackSelectionWhenPersistenceFails() async {
        let preferencesStore = FailingSelectionPreferencesStore(
            fallback: InMemoryPreferencesStore(selectedSystemCalendarIDs: ["feishu"])
        )
        let access = StubSystemCalendarAccess(
            authorizationState: .authorized,
            calendars: [
                calendar(id: "feishu", title: "飞书日历", suggested: true),
                calendar(id: "personal", title: "个人", suggested: false)
            ]
        )
        let controller = SystemCalendarConnectionController(
            calendarAccess: access,
            preferencesStore: preferencesStore,
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            autoRefreshOnStart: false
        )

        await controller.refreshState()
        await controller.setCalendarSelection(calendarID: "personal", isSelected: true)
        let storedCalendarIDs = await preferencesStore.loadSelectedSystemCalendarIDs()

        XCTAssertEqual(controller.selectedCalendarIDs, ["feishu"])
        XCTAssertEqual(storedCalendarIDs, ["feishu"])
        XCTAssertEqual(
            controller.selectionPersistenceState,
            .failed(message: "未能更新日历选择，已恢复到上一次保存状态")
        )
    }

    /// 验证系统日历数据源在未选择任何日历时，会保持未配置状态而不是误判成失败。
    func testSystemCalendarMeetingSourceReturnsUnconfiguredWithoutSelection() async {
        let preferencesStore = InMemoryPreferencesStore(selectedSystemCalendarIDs: [])
        let source = SystemCalendarMeetingSource(
            calendarAccess: StubSystemCalendarAccess(authorizationState: .authorized),
            preferencesStore: preferencesStore
        )

        let healthState = await source.healthState()

        XCTAssertEqual(healthState, .unconfigured(message: "尚未选择需要纳入提醒的系统日历"))
    }

    /// 验证系统日历事件能被统一标准化成会议，并把来源信息标成具体系统日历。
    func testSystemCalendarMeetingSourceRefreshNormalizesPayloadsIntoMeetings() async throws {
        let preferencesStore = InMemoryPreferencesStore(selectedSystemCalendarIDs: ["feishu"])
        let access = StubSystemCalendarAccess(
            authorizationState: .authorized,
            calendars: [calendar(id: "feishu", title: "飞书日历", suggested: true)],
            events: [
                (
                    calendar: calendar(id: "feishu", title: "飞书日历", suggested: true),
                    payload: SystemCalendarEventPayload(
                        identifier: "event-1",
                        title: "团队周会",
                        startAt: fixedNow().addingTimeInterval(15 * 60),
                        endAt: fixedNow().addingTimeInterval(45 * 60),
                        timeZoneIdentifier: "Asia/Shanghai",
                        isAllDay: false,
                        isCancelled: false,
                        primaryURL: URL(string: "https://meet.feishu.cn/abc"),
                        notes: "会议详情 https://example.com/detail"
                    )
                )
            ]
        )
        let source = SystemCalendarMeetingSource(
            calendarAccess: access,
            preferencesStore: preferencesStore
        )

        let snapshot = try await source.refresh(trigger: .manualRefresh, now: fixedNow())

        XCTAssertEqual(snapshot.meetings.count, 1)
        XCTAssertEqual(snapshot.meetings.first?.title, "团队周会")
        XCTAssertEqual(snapshot.meetings.first?.source.sourceIdentifier, "feishu")
        XCTAssertEqual(snapshot.meetings.first?.links.count, 2)
        XCTAssertEqual(snapshot.healthState, .ready(message: "已从 1 个系统日历读取会议"))
    }

    /// 验证 URL 提取和标题兜底逻辑能在不依赖 EventKit 的情况下直接被规则测试锁住。
    func testEventNormalizerUsesFallbackTitleAndDeduplicatesLinks() {
        let meeting = SystemCalendarEventNormalizer.makeMeetingRecord(
            from: SystemCalendarEventPayload(
                identifier: "event-2",
                title: "   ",
                startAt: fixedNow(),
                endAt: fixedNow().addingTimeInterval(30 * 60),
                timeZoneIdentifier: nil,
                isAllDay: false,
                isCancelled: false,
                primaryURL: URL(string: "https://example.com/detail"),
                notes: "重复链接 https://example.com/detail"
            ),
            calendar: calendar(id: "local", title: "工作", suggested: false)
        )

        XCTAssertEqual(meeting.title, "未命名会议")
        XCTAssertEqual(meeting.links.count, 1)
        XCTAssertEqual(meeting.links.first?.kind, .web)
    }

    /// 验证协议默认 `refresh()` 完成后 `loadingState` 归位 `false`，正常完成时 `errorMessage` 为 `nil`。
    func testRefreshTogglesLoadingStateAndClearsErrorOnSuccess() async {
        let controller = SystemCalendarConnectionController(
            calendarAccess: StubSystemCalendarAccess(
                authorizationState: .authorized,
                calendars: [calendar(id: "feishu", title: "飞书日历", suggested: true)]
            ),
            preferencesStore: InMemoryPreferencesStore(),
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            autoRefreshOnStart: false
        )

        await controller.refresh()

        XCTAssertFalse(controller.loadingState, "loadingState 应在 refresh() 完成后归位 false")
        XCTAssertNil(controller.errorMessage, "正常完成时 errorMessage 应为 nil")
    }

    /// 验证用户选择日历后，控制器会通过 `RefreshEventBus` 向总线发布 `.manualRefresh` 事件。
    func testCalendarSelectionPublishesManualRefreshEventOnBus() async {
        let bus = RefreshEventBus()
        var receivedTriggers: [RefreshTrigger] = []
        let cancellable = bus.publisher.sink { receivedTriggers.append($0) }

        let controller = SystemCalendarConnectionController(
            calendarAccess: StubSystemCalendarAccess(
                authorizationState: .authorized,
                calendars: [
                    calendar(id: "feishu", title: "飞书日历", suggested: true),
                    calendar(id: "personal", title: "个人", suggested: false)
                ]
            ),
            preferencesStore: InMemoryPreferencesStore(selectedSystemCalendarIDs: ["feishu"]),
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            refreshEventBus: bus,
            autoRefreshOnStart: false
        )

        await controller.refreshState()
        await controller.setCalendarSelection(calendarID: "personal", isSelected: true)

        XCTAssertEqual(receivedTriggers, [.manualRefresh], "日历选择变化后应向总线发布 .manualRefresh")
        _ = cancellable
    }

    /// 统一生成测试用系统日历描述符。
    private func calendar(id: String, title: String, suggested: Bool) -> SystemCalendarDescriptor {
        SystemCalendarDescriptor(
            id: id,
            title: title,
            sourceTitle: "测试账户",
            sourceTypeLabel: "CalDAV",
            isSuggestedByDefault: suggested
        )
    }

    /// 所有桥接层测试共享同一个固定时间。
    private func fixedNow() -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 9, minute: 0))!
    }
}

/// 用纯 Swift stub 替换真实 EventKit 访问层，让桥接测试不依赖机器权限或真实日历。
@MainActor
private final class StubSystemCalendarAccess: SystemCalendarAccessing {
    /// 测试预设的授权状态。
    var authorizationState: SystemCalendarAuthorizationState
    /// 测试预设的系统日历候选。
    var calendars: [SystemCalendarDescriptor]
    /// 测试预设的事件载荷。
    var events: [(calendar: SystemCalendarDescriptor, payload: SystemCalendarEventPayload)]

    init(
        authorizationState: SystemCalendarAuthorizationState,
        calendars: [SystemCalendarDescriptor] = [],
        events: [(calendar: SystemCalendarDescriptor, payload: SystemCalendarEventPayload)] = []
    ) {
        self.authorizationState = authorizationState
        self.calendars = calendars
        self.events = events
    }

    func currentAuthorizationState() -> SystemCalendarAuthorizationState {
        authorizationState
    }

    func requestReadAccess() async throws -> SystemCalendarAuthorizationState {
        authorizationState
    }

    func fetchCalendars() -> [SystemCalendarDescriptor] {
        calendars
    }

    func fetchEventPayloads(
        start: Date,
        end: Date,
        calendarIDs: Set<String>
    ) throws -> [(calendar: SystemCalendarDescriptor, payload: SystemCalendarEventPayload)] {
        events.filter { calendarIDs.contains($0.calendar.id) }
    }
}

/// 这些桥接层测试同样使用固定时钟，避免“最近更新时间”依赖真实当前时间。
private struct FixedDateProvider: DateProviding {
    /// 测试注入的固定当前时间。
    let currentDate: Date

    /// 直接返回固定时间。
    func now() -> Date {
        currentDate
    }
}

/// 这个测试 actor 会在保存日历选择时故意抛错，
/// 让我们验证控制器的乐观更新和失败回滚是否保持一致。
actor FailingSelectionPreferencesStore: PreferencesStore {
    private let fallback: InMemoryPreferencesStore

    init(fallback: InMemoryPreferencesStore) {
        self.fallback = fallback
    }

    func loadReminderPreferences() async -> ReminderPreferences {
        await fallback.loadReminderPreferences()
    }

    func saveReminderPreferences(_ reminderPreferences: ReminderPreferences) async throws {
        try await fallback.saveReminderPreferences(reminderPreferences)
    }

    func loadSelectedSystemCalendarIDs() async -> Set<String> {
        await fallback.loadSelectedSystemCalendarIDs()
    }

    func saveSelectedSystemCalendarIDs(_ identifiers: Set<String>) async throws {
        throw PersistenceFailure()
    }

    func hasStoredSelectedSystemCalendarIDs() async -> Bool {
        await fallback.hasStoredSelectedSystemCalendarIDs()
    }

    func loadLastSuccessfulRefreshAt() async -> Date? {
        await fallback.loadLastSuccessfulRefreshAt()
    }

    func saveLastSuccessfulRefreshAt(_ date: Date?) async throws {
        try await fallback.saveLastSuccessfulRefreshAt(date)
    }

    func loadSoundProfiles() async -> [SoundProfile] {
        await fallback.loadSoundProfiles()
    }

    func saveSoundProfiles(_ soundProfiles: [SoundProfile]) async throws {
        try await fallback.saveSoundProfiles(soundProfiles)
    }

    func loadSelectedSoundProfileID() async -> String? {
        await fallback.loadSelectedSoundProfileID()
    }

    func saveSelectedSoundProfileID(_ soundProfileID: String?) async throws {
        try await fallback.saveSelectedSoundProfileID(soundProfileID)
    }
}

/// 用一个稳定的错误类型驱动失败分支，避免测试依赖系统错误文案。
private struct PersistenceFailure: Error {}
