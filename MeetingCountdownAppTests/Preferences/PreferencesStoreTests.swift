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

    /// 验证新增的提醒偏好字段和最近成功刷新时间都能稳定往返。
    func testUserDefaultsPreferencesStorePersistsReminderPreferencesAndLastRefreshAt() async throws {
        let suiteName = "PreferencesStoreTests.\(UUID().uuidString)"
        let cleanupUserDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        cleanupUserDefaults.removePersistentDomain(forName: suiteName)

        defer {
            cleanupUserDefaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsPreferencesStore(suiteName: suiteName)
        let reminderPreferences = ReminderPreferences(
            countdownOverrideSeconds: 15,
            globalReminderEnabled: true,
            isMuted: false,
            playSoundOnlyWhenHeadphonesConnected: true,
            onlyForMeetingsWithVideoLink: true,
            skipDeclinedMeetings: false,
            interfaceLanguage: .english
        )
        let lastRefreshAt = Date(timeIntervalSince1970: 1_234_567)

        try await store.saveReminderPreferences(reminderPreferences)
        try await store.saveLastSuccessfulRefreshAt(lastRefreshAt)

        let loadedPreferences = await store.loadReminderPreferences()
        let loadedLastRefreshAt = await store.loadLastSuccessfulRefreshAt()
        let bootstrapUserDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        XCTAssertEqual(loadedPreferences, reminderPreferences)
        XCTAssertEqual(loadedPreferences.interfaceLanguage, .english)
        XCTAssertEqual(loadedLastRefreshAt, lastRefreshAt)
        XCTAssertEqual(
            UserDefaultsPreferencesStore.bootstrapLastSuccessfulRefreshAt(userDefaults: bootstrapUserDefaults),
            lastRefreshAt
        )
    }

    /// 验证提醒音频列表和当前选中音频都能稳定往返。
    func testUserDefaultsPreferencesStorePersistsSoundProfilesAndSelection() async throws {
        let suiteName = "PreferencesStoreTests.\(UUID().uuidString)"
        let cleanupUserDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        cleanupUserDefaults.removePersistentDomain(forName: suiteName)

        defer {
            cleanupUserDefaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsPreferencesStore(suiteName: suiteName)
        let soundProfiles = [
            SoundProfile(
                id: "custom-sound",
                displayName: "gong.wav",
                storage: .imported(fileName: "custom-sound.wav"),
                duration: 12,
                createdAt: Date(timeIntervalSince1970: 7_654_321)
            )
        ]

        try await store.saveSoundProfiles(soundProfiles)
        try await store.saveSelectedSoundProfileID(soundProfiles[0].id)

        let loadedSoundProfiles = await store.loadSoundProfiles()
        let loadedSelectedSoundProfileID = await store.loadSelectedSoundProfileID()

        XCTAssertEqual(loadedSoundProfiles, soundProfiles)
        XCTAssertEqual(loadedSelectedSoundProfileID, soundProfiles[0].id)
    }

    /// 全新 UserDefaults 第一次走 load 应当被打上当前 schema 版本号。
    /// 这条测试守住 E-5：今后 schema 升级时如果 `migrateIfNeeded()` 没有跑，将立即失败。
    func testFreshUserDefaultsBootstrapsToCurrentSchemaVersion() async throws {
        let suiteName = "test.preferences.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        // 全新存档：schema 版本号 key 在 load 之前不应该存在。
        XCTAssertNil(userDefaults.object(forKey: "preferences_schema_version"))

        let store = UserDefaultsPreferencesStore(suiteName: suiteName)
        _ = await store.loadReminderPreferences()

        // 由于 `init(suiteName:)` 内部会 `?? .standard`，这里再 unwrap 一次同名 suite 来读 key。
        let storedVersion = userDefaults.object(forKey: "preferences_schema_version") as? Int
        XCTAssertEqual(storedVersion, 1, "首次 load 之后应当把 schema 版本号写成当前值")
    }

    /// 已存在偏好但缺少 schema 版本号时（即“升级到带 schema 版本号的版本”那一刻），
    /// migration 必须补上当前版本号且不破坏既有数据。
    func testExistingPreferencesWithoutSchemaVersionTriggersMigration() async throws {
        let suiteName = "test.preferences.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        // 模拟“老版本写过偏好但还没有 schema_version 概念”的存档。
        userDefaults.set(["legacy-calendar-1", "legacy-calendar-2"], forKey: "connection_preferences.selected_system_calendar_ids")
        userDefaults.set(false, forKey: "reminder_preferences.global_reminder_enabled")

        XCTAssertNil(userDefaults.object(forKey: "preferences_schema_version"))

        let store = UserDefaultsPreferencesStore(suiteName: suiteName)
        let loadedReminder = await store.loadReminderPreferences()
        let loadedCalendarIDs = await store.loadSelectedSystemCalendarIDs()

        // migration 必须写入当前 schema 版本号。
        let storedVersion = userDefaults.object(forKey: "preferences_schema_version") as? Int
        XCTAssertEqual(storedVersion, 1)

        // 既有数据必须原样保留——migration 是 no-op，不该把字段重置为默认值。
        XCTAssertEqual(loadedCalendarIDs, ["legacy-calendar-1", "legacy-calendar-2"])
        XCTAssertEqual(loadedReminder.globalReminderEnabled, false)
    }
}
