import Foundation
import XCTest
@testable import FeishuMeetingCountdown

/// 这些测试验证 Phase 2 新增的非敏感连接配置持久化是否稳定。
final class PreferencesStoreTests: XCTestCase {
    /// 验证 `UserDefaultsPreferencesStore` 能保存并恢复系统日历选择。
    func testUserDefaultsPreferencesStorePersistsSelectedSystemCalendars() async throws {
        let suiteName = "PreferencesStoreTests.\(UUID().uuidString)"
        let cleanupUserDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        cleanupUserDefaults.removePersistentDomain(forName: suiteName)

        defer {
            cleanupUserDefaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsPreferencesStore(suiteName: suiteName)

        try await store.saveSelectedSystemCalendarIDs(["calendar-a", "calendar-b"])

        let selectedCalendarIDs = await store.loadSelectedSystemCalendarIDs()
        let bootstrapUserDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        XCTAssertEqual(selectedCalendarIDs, ["calendar-a", "calendar-b"])
        XCTAssertEqual(
            UserDefaultsPreferencesStore.bootstrapSelectedSystemCalendarIDs(userDefaults: bootstrapUserDefaults),
            ["calendar-a", "calendar-b"]
        )
    }
}
