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
}
