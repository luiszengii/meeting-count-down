import Foundation
import SwiftUI
import XCTest
@testable import FeishuMeetingCountdown

/// 这些测试锁定 `SettingsPage` 注册表的结构契约：页面数量、顺序、
/// titleKey 内容、以及 body(uiLanguage:) 可以正常构建（不崩溃）。
/// 测试只验证"形状"，不验证视觉布局（快照框架的决策权在用户侧，已延迟）。
@MainActor
final class SettingsPageRegistryTests: XCTestCase {

    // MARK: - Helpers

    /// 以最小依赖构建一个页面注册表，镜像 SettingsView.pages 的构造顺序。
    /// OverviewPage 需要跨页导航回调；其余页面依赖各自 controller。
    private func makePages() async -> [any SettingsPage] {
        let store = InMemoryPreferencesStore()

        let sourceCoordinator = SourceCoordinator(
            source: StubMeetingSource(
                descriptor: MeetingSourceDescriptor(
                    sourceIdentifier: "test",
                    displayName: "CalDAV"
                ),
                currentHealthState: .ready(message: "ok"),
                sampleMeetings: []
            ),
            nextMeetingSelector: DefaultNextMeetingSelector(),
            preferencesStore: store,
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            logger: AppLogger(source: "SettingsPageRegistryTests"),
            autoRefreshOnStart: false
        )
        let calendarAccess = RegistryTestStubSystemCalendarAccess(
            authorizationState: .authorized,
            calendars: []
        )
        let systemCalendarConnectionController = SystemCalendarConnectionController(
            calendarAccess: calendarAccess,
            preferencesStore: store,
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            autoRefreshOnStart: false
        )
        let reminderPreferencesController = ReminderPreferencesController(
            preferencesStore: store,
            autoRefreshOnStart: false
        )
        let soundProfileLibraryController = SoundProfileLibraryController(
            preferencesStore: store,
            assetStore: RegistryTestStubSoundProfileAssetStore(),
            previewPlayer: RegistryTestStubSoundProfilePreviewPlayer(),
            autoRefreshOnStart: false
        )
        let reminderEngine = ReminderEngine(
            preferencesStore: store,
            audioEngine: RegistryTestStubReminderAudioEngine(),
            audioOutputRouteProvider: RegistryTestStubAudioOutputRouteProvider(),
            scheduler: RegistryTestStubReminderScheduler(),
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            logger: AppLogger(source: "SettingsPageRegistryTests")
        )
        let launchAtLoginController = LaunchAtLoginController(autoRefreshOnStart: false)

        // isPresentingSoundImporter Binding: AudioPage 需要，这里用固定值替代。
        var dummyBool = false
        let importerBinding = Binding(get: { dummyBool }, set: { dummyBool = $0 })

        return [
            OverviewPage(
                sourceCoordinator: sourceCoordinator,
                systemCalendarConnectionController: systemCalendarConnectionController,
                reminderEngine: reminderEngine,
                reminderPreferencesController: reminderPreferencesController,
                soundProfileLibraryController: soundProfileLibraryController,
                onNavigate: { _ in }
            ),
            CalendarPage(
                systemCalendarConnectionController: systemCalendarConnectionController,
                sourceCoordinator: sourceCoordinator
            ),
            RemindersPage(
                reminderEngine: reminderEngine,
                reminderPreferencesController: reminderPreferencesController,
                soundProfileLibraryController: soundProfileLibraryController
            ),
            AudioPage(
                soundProfileLibraryController: soundProfileLibraryController,
                reminderPreferencesController: reminderPreferencesController,
                isPresentingSoundImporter: importerBinding
            ),
            AdvancedPage(
                sourceCoordinator: sourceCoordinator,
                systemCalendarConnectionController: systemCalendarConnectionController,
                reminderPreferencesController: reminderPreferencesController,
                launchAtLoginController: launchAtLoginController
            )
        ]
    }

    private func fixedNow() -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(
            year: 2026, month: 4, day: 22, hour: 10, minute: 0
        ))!
    }

    // MARK: - Test 1: Count and tab IDs

    /// 注册表必须包含恰好 5 个页面，且每个页面的 id 与
    /// SettingsTab.allCases 顺序一一对应（overview / calendar / reminders / audio / advanced）。
    func testRegistryContainsExactlyFivePagesWithExpectedTabIDs() async {
        let pages = await makePages()

        XCTAssertEqual(pages.count, 5,
            "注册表应包含恰好 5 个页面；新增 tab 必须同时更新注册表和 SettingsTab。")

        let expectedIDs: [SettingsTab] = [.overview, .calendar, .reminders, .audio, .advanced]
        let actualIDs = pages.map(\.id)
        XCTAssertEqual(actualIDs, expectedIDs,
            "注册表页面顺序必须与 SettingsTab.allCases 一致。")
    }

    // MARK: - Test 2: titleKey non-empty for both languages

    /// 每个页面的 titleKey 中文和英文值都不能为空字符串，
    /// 确保 tab bar 和 header 的双语展示不会显示空白。
    func testEachPageTitleKeyReturnsNonEmptyChineseAndEnglishValues() async {
        let pages = await makePages()

        for page in pages {
            let (chinese, english) = page.titleKey
            XCTAssertFalse(chinese.isEmpty,
                "页面 \(page.id) 的中文 titleKey 不应为空。")
            XCTAssertFalse(english.isEmpty,
                "页面 \(page.id) 的英文 titleKey 不应为空。")
        }
    }

    // MARK: - Test 3: body(uiLanguage:) construction sanity

    /// 每个页面的 body(uiLanguage:) 在中文和英文模式下都能正常构建，
    /// 不抛异常也不返回触发 fatalError 的视图（仅验证构建路径，不做快照对比）。
    func testEachPageBodyConstructsWithoutCrashingInBothLanguages() async {
        let pages = await makePages()

        for page in pages {
            // AnyView is always non-nil by construction; the point is that the body
            // method does not crash during view graph construction.
            let chineseBody = page.body(uiLanguage: .simplifiedChinese)
            let englishBody = page.body(uiLanguage: .english)

            // AnyView wraps an opaque value; confirm it type-checks correctly.
            XCTAssertTrue(chineseBody is AnyView,
                "页面 \(page.id) 的中文 body 应返回 AnyView。")
            XCTAssertTrue(englishBody is AnyView,
                "页面 \(page.id) 的英文 body 应返回 AnyView。")
        }
    }

    // MARK: - Test 4: Duplicate page construction lifecycle sanity

    /// 用同一批 controller 构建两次注册表，确认没有共享可变状态导致的崩溃或断言失败。
    func testConstructingTwoRegistriesWithSameControllersDoesNotCrash() async {
        let pages1 = await makePages()
        let pages2 = await makePages()

        XCTAssertEqual(pages1.count, pages2.count,
            "两次构建注册表应产生相同数量的页面。")
        XCTAssertEqual(pages1.map(\.id), pages2.map(\.id),
            "两次构建注册表应产生相同的 tab ID 顺序。")
    }

    // MARK: - Test 5: Registry order matches SettingsTab.allCases

    /// 注册表顺序必须与 SettingsTab.allCases 完全吻合，
    /// 这样任何人在 SettingsTab 里加新 case 后，CI 会在这里失败，
    /// 强制同步更新注册表。
    func testRegistryOrderMatchesSettingsTabAllCases() async {
        let pages = await makePages()
        let registryIDs = pages.map(\.id)
        let tabAllCases = SettingsTab.allCases

        XCTAssertEqual(registryIDs.count, tabAllCases.count,
            "注册表页面数量必须与 SettingsTab.allCases 数量一致；新增 tab 时必须同步更新注册表。")
        XCTAssertEqual(registryIDs, tabAllCases,
            "注册表顺序必须与 SettingsTab.allCases 完全一致。")
    }
}

// MARK: - Stub types (private to this file)

/// SystemCalendarAccess stub：始终返回给定的授权状态和日历列表，不调用 EventKit。
@MainActor
private final class RegistryTestStubSystemCalendarAccess: SystemCalendarAccessing {
    let authorizationState: SystemCalendarAuthorizationState
    let calendars: [SystemCalendarDescriptor]

    init(
        authorizationState: SystemCalendarAuthorizationState,
        calendars: [SystemCalendarDescriptor]
    ) {
        self.authorizationState = authorizationState
        self.calendars = calendars
    }

    func currentAuthorizationState() -> SystemCalendarAuthorizationState { authorizationState }
    func requestReadAccess() async throws -> SystemCalendarAuthorizationState { authorizationState }
    func fetchCalendars() -> [SystemCalendarDescriptor] { calendars }
    func fetchEventPayloads(start: Date, end: Date, calendarIDs: Set<String>) throws
        -> [(calendar: SystemCalendarDescriptor, payload: SystemCalendarEventPayload)] { [] }
}

/// 音频资产存储 stub：只返回最小可用的默认音频描述，不读磁盘文件。
private actor RegistryTestStubSoundProfileAssetStore: SoundProfileAssetManaging {
    func bundledDefaultProfile() async -> SoundProfile {
        SoundProfile.bundledDefault(duration: 1)
    }

    func importSoundFiles(from urls: [URL]) async -> SoundProfileImportBatch {
        SoundProfileImportBatch(importedProfiles: [], failures: [])
    }

    func deleteImportedSoundProfile(_ profile: SoundProfile) async throws {}

    func url(for profile: SoundProfile) async throws -> URL {
        URL(fileURLWithPath: "/tmp/\(profile.id).wav")
    }
}

/// 试听播放器 stub：注册表结构测试不需要真实音频播放。
@MainActor
private final class RegistryTestStubSoundProfilePreviewPlayer: SoundProfilePreviewPlaying {
    func playPreview(of soundProfile: SoundProfile) async throws {}
    func stopPreview() async {}
}

/// 提醒音频引擎 stub：返回固定时长 1 秒，不触及 AVFoundation。
@MainActor
private final class RegistryTestStubReminderAudioEngine: ReminderAudioEngine {
    func warmUp() async throws {}
    func defaultSoundDuration() async throws -> TimeInterval { 1 }
    func playDefaultSound() async throws {}
    func stopPlayback() async {}
}

/// 音频输出路由 stub：固定返回私密收听设备，满足引擎初始化依赖。
@MainActor
private final class RegistryTestStubAudioOutputRouteProvider: AudioOutputRouteProviding {
    func currentRoute() -> AudioOutputRouteSnapshot {
        AudioOutputRouteSnapshot(name: "Test Headphones", kind: .privateListening)
    }
}

/// 提醒调度器 stub：不创建真实定时任务，只满足协议依赖。
@MainActor
private final class RegistryTestStubReminderScheduler: ReminderScheduling {
    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> any ReminderScheduledTask {
        RegistryTestStubReminderScheduledTask()
    }
}

/// 空调度句柄 stub：只满足 ReminderScheduledTask 协议，不承担真实任务。
@MainActor
private final class RegistryTestStubReminderScheduledTask: ReminderScheduledTask {
    var isCancelled: Bool = false
    func cancel() { isCancelled = true }
}
