import Combine
import Foundation
import XCTest
@testable import FeishuMeetingCountdown

/// 这些测试锁定 `ReminderPreferencesController` 中 `AsyncStateController` 协议默认行为。
@MainActor
final class ReminderPreferencesControllerTests: XCTestCase {
    /// 验证协议默认 `refresh()` 完成后 `loadingState` 归位 `false`，正常完成时 `errorMessage` 为 `nil`。
    func testRefreshTogglesLoadingStateAndClearsErrorOnSuccess() async {
        let controller = ReminderPreferencesController(
            preferencesStore: InMemoryPreferencesStore(),
            autoRefreshOnStart: false
        )

        await controller.refresh()

        XCTAssertFalse(controller.loadingState, "loadingState 应在 refresh() 完成后归位 false")
        XCTAssertNil(controller.errorMessage, "正常完成时 errorMessage 应为 nil")
    }

    /// 验证保存失败时，`errorMessage` 会被填充且 `isSavingState` 归位 `false`。
    /// 注意：`performRefresh()` 调用的 `loadReminderPreferences()` 是非抛出接口，
    /// 因此 `refresh()` 不会产生 `errorMessage`；错误捕获路径通过写入操作触发验证。
    func testSavePreferencesFailureSetsErrorMessage() async {
        let failingStore = FailingSavePreferencesStore()
        let controller = ReminderPreferencesController(
            preferencesStore: failingStore,
            autoRefreshOnStart: false
        )

        await controller.refresh()
        // 触发写入路径（会抛错）来验证错误捕获
        await controller.setGlobalReminderEnabled(!ReminderPreferences.default.globalReminderEnabled)

        XCTAssertFalse(controller.isSavingState, "isSavingState 应在操作完成后归位 false")
        XCTAssertNotNil(controller.errorMessage, "保存失败时 errorMessage 应被填充")
    }

    /// 验证成功保存偏好后，控制器会向 `RefreshEventBus` 发布 `.preferencesChanged` 事件。
    func testSavePreferencesPublishesPreferencesChangedEventOnBus() async {
        let bus = RefreshEventBus()
        var receivedTriggers: [RefreshTrigger] = []
        let cancellable = bus.publisher.sink { receivedTriggers.append($0) }

        let controller = ReminderPreferencesController(
            preferencesStore: InMemoryPreferencesStore(),
            refreshEventBus: bus,
            autoRefreshOnStart: false
        )

        await controller.refresh()
        await controller.setGlobalReminderEnabled(!ReminderPreferences.default.globalReminderEnabled)

        XCTAssertEqual(receivedTriggers, [.preferencesChanged], "保存成功后应向总线发布 .preferencesChanged")
        _ = cancellable
    }

    /// 验证语言切换（notifyUpstream: false 路径）不会向总线发布事件。
    func testSetInterfaceLanguageDoesNotPublishEventOnBus() async {
        let bus = RefreshEventBus()
        var receivedTriggers: [RefreshTrigger] = []
        let cancellable = bus.publisher.sink { receivedTriggers.append($0) }

        let controller = ReminderPreferencesController(
            preferencesStore: InMemoryPreferencesStore(),
            refreshEventBus: bus,
            autoRefreshOnStart: false
        )

        await controller.refresh()
        // 切换到英文（默认值是 simplifiedChinese），确保偏好值确实发生了变化
        await controller.setInterfaceLanguage(.english)

        XCTAssertTrue(receivedTriggers.isEmpty, "语言切换不应触发上游刷新信号")
        _ = cancellable
    }
}

/// 让 `saveReminderPreferences` 总是抛错，用于验证写入路径的错误捕获。
actor FailingSavePreferencesStore: PreferencesStore {
    private var preferences: ReminderPreferences = .default

    func loadReminderPreferences() async -> ReminderPreferences { preferences }

    func saveReminderPreferences(_ reminderPreferences: ReminderPreferences) async throws {
        throw ReminderControllerTestFailure()
    }

    func loadSelectedSystemCalendarIDs() async -> Set<String> { [] }

    func saveSelectedSystemCalendarIDs(_ identifiers: Set<String>) async throws {}

    func hasStoredSelectedSystemCalendarIDs() async -> Bool { false }

    func loadLastSuccessfulRefreshAt() async -> Date? { nil }

    func saveLastSuccessfulRefreshAt(_ date: Date?) async throws {}

    func loadSoundProfiles() async -> [SoundProfile] { [] }

    func saveSoundProfiles(_ soundProfiles: [SoundProfile]) async throws {}

    func loadSelectedSoundProfileID() async -> String? { nil }

    func saveSelectedSoundProfileID(_ soundProfileID: String?) async throws {}
}

/// 稳定错误类型，避免测试依赖系统错误文案。
private struct ReminderControllerTestFailure: LocalizedError {
    var errorDescription: String? { "测试注入的保存失败" }
}
