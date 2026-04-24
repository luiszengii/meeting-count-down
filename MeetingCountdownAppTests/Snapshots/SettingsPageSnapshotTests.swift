import AppKit
import SnapshotTesting
import SwiftUI
import XCTest
@testable import FeishuMeetingCountdown

/// 对五个 SettingsPage 做视觉基线快照，覆盖亮色 + 暗色模式。
/// 共 5 页 × 2 模式 = 10 条快照测试。
///
/// 技术说明：
/// - macOS 上 SnapshotTesting 没有 SwiftUI 的直接策略（该策略只针对 iOS/tvOS），
///   需要通过 NSHostingController 桥接，再用 NSViewController.image(size:) 策略。
/// - 亮/暗模式通过在截图前后切换 NSView.appearance 来实现，
///   不影响其他测试，也不依赖系统全局外观设置。
/// - 第一次运行会在 __Snapshots__ 目录下生成 PNG 基线；之后的运行会做对比断言。
@MainActor
final class SettingsPageSnapshotTests: XCTestCase {

    // MARK: - Constants

    /// 设置窗口的标准宽高（对应 SettingsView 的预设尺寸）。
    private static let snapshotSize = CGSize(width: 1040, height: 720)

    // MARK: - Pages setup (mirrors SettingsPageRegistryTests.makePages)

    private func makePages() async -> [any SettingsPage] {
        let store = InMemoryPreferencesStore()

        let sourceCoordinator = SourceCoordinator(
            source: StubMeetingSource(
                descriptor: MeetingSourceDescriptor(
                    sourceIdentifier: "snapshot-test",
                    displayName: "CalDAV (Snapshot)"
                ),
                currentHealthState: .ready(message: "ok"),
                sampleMeetings: []
            ),
            nextMeetingSelector: DefaultNextMeetingSelector(),
            preferencesStore: store,
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            logger: AppLogger(source: "SettingsPageSnapshotTests"),
            autoRefreshOnStart: false
        )
        let calendarAccess = SnapshotStubSystemCalendarAccess(
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
            assetStore: SnapshotStubSoundProfileAssetStore(),
            previewPlayer: SnapshotStubSoundProfilePreviewPlayer(),
            autoRefreshOnStart: false
        )
        let reminderEngine = ReminderEngine(
            preferencesStore: store,
            audioEngine: SnapshotStubReminderAudioEngine(),
            audioOutputRouteProvider: SnapshotStubAudioOutputRouteProvider(),
            scheduler: SnapshotStubReminderScheduler(),
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            logger: AppLogger(source: "SettingsPageSnapshotTests")
        )
        let launchAtLoginController = LaunchAtLoginController(autoRefreshOnStart: false)

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
            year: 2026, month: 4, day: 23, hour: 10, minute: 0
        ))!
    }

    // MARK: - Snapshot helpers

    /// SnapshotTesting 在 Swift 6 + xcodebuild 环境下 `#file` 可能产生相对路径，
    /// 导致无法在正确位置创建 `__Snapshots__` 目录。
    /// 通过显式传入 `snapshotDirectory` 解决此问题。
    private static let snapshotDirectory: String = {
        // __FILE__ 绝对路径是编译时写入的；如果为相对路径则回退到源码根目录约定。
        let filePath = #filePath
        if filePath.hasPrefix("/") {
            // 绝对路径：取测试文件所在目录下的 __Snapshots__/SettingsPageSnapshotTests
            let dir = (filePath as NSString).deletingLastPathComponent
            return "\(dir)/__Snapshots__/SettingsPageSnapshotTests"
        }
        // 相对路径 fallback：直接使用源码目录约定
        return "/Users/luiszeng/Documents/GitHub/meeting-count-down/MeetingCountdownAppTests/Snapshots/__Snapshots__/SettingsPageSnapshotTests"
    }()

    /// 把 AnyView 包进 NSHostingController，设置外观，截图。
    /// 使用 `verifySnapshot` 而不是 `assertSnapshot`，以便显式传入 `snapshotDirectory`
    /// 解决 Swift 6 + xcodebuild 下 `#filePath` 可能为相对路径的问题。
    private func assertPageSnapshot(
        _ view: AnyView,
        appearance: NSAppearance,
        named name: String,
        file: StaticString = #file,
        testName: String = #function,
        line: UInt = #line
    ) {
        let hostingController = NSHostingController(rootView: view)
        hostingController.view.appearance = appearance
        if let failure = verifySnapshot(
            of: hostingController,
            as: .image(size: Self.snapshotSize),
            named: name,
            snapshotDirectory: Self.snapshotDirectory,
            file: file,
            testName: testName,
            line: line
        ) {
            XCTFail(failure, file: file, line: line)
        }
    }

    // MARK: - Overview

    func testOverviewPageLight() async {
        let pages = await makePages()
        let page = pages[0]
        assertPageSnapshot(
            page.body(uiLanguage: .simplifiedChinese),
            appearance: NSAppearance(named: .aqua)!,
            named: "light"
        )
    }

    func testOverviewPageDark() async {
        let pages = await makePages()
        let page = pages[0]
        assertPageSnapshot(
            page.body(uiLanguage: .simplifiedChinese),
            appearance: NSAppearance(named: .darkAqua)!,
            named: "dark"
        )
    }

    // MARK: - Calendar

    func testCalendarPageLight() async {
        let pages = await makePages()
        let page = pages[1]
        assertPageSnapshot(
            page.body(uiLanguage: .simplifiedChinese),
            appearance: NSAppearance(named: .aqua)!,
            named: "light"
        )
    }

    func testCalendarPageDark() async {
        let pages = await makePages()
        let page = pages[1]
        assertPageSnapshot(
            page.body(uiLanguage: .simplifiedChinese),
            appearance: NSAppearance(named: .darkAqua)!,
            named: "dark"
        )
    }

    // MARK: - Reminders

    func testRemindersPageLight() async {
        let pages = await makePages()
        let page = pages[2]
        assertPageSnapshot(
            page.body(uiLanguage: .simplifiedChinese),
            appearance: NSAppearance(named: .aqua)!,
            named: "light"
        )
    }

    func testRemindersPageDark() async {
        let pages = await makePages()
        let page = pages[2]
        assertPageSnapshot(
            page.body(uiLanguage: .simplifiedChinese),
            appearance: NSAppearance(named: .darkAqua)!,
            named: "dark"
        )
    }

    // MARK: - Audio

    /// AudioPage 的 isPresentingSoundImporter Binding 传入 .constant(false)，
    /// 文件导入弹窗不会出现在快照里。
    func testAudioPageLight() async {
        let pages = await makePages()
        let page = pages[3]
        assertPageSnapshot(
            page.body(uiLanguage: .simplifiedChinese),
            appearance: NSAppearance(named: .aqua)!,
            named: "light"
        )
    }

    func testAudioPageDark() async {
        let pages = await makePages()
        let page = pages[3]
        assertPageSnapshot(
            page.body(uiLanguage: .simplifiedChinese),
            appearance: NSAppearance(named: .darkAqua)!,
            named: "dark"
        )
    }

    // MARK: - Advanced

    func testAdvancedPageLight() async {
        let pages = await makePages()
        let page = pages[4]
        assertPageSnapshot(
            page.body(uiLanguage: .simplifiedChinese),
            appearance: NSAppearance(named: .aqua)!,
            named: "light"
        )
    }

    func testAdvancedPageDark() async {
        let pages = await makePages()
        let page = pages[4]
        assertPageSnapshot(
            page.body(uiLanguage: .simplifiedChinese),
            appearance: NSAppearance(named: .darkAqua)!,
            named: "dark"
        )
    }
}

// MARK: - Stub types (private to this file)

@MainActor
private final class SnapshotStubSystemCalendarAccess: SystemCalendarAccessing {
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

private actor SnapshotStubSoundProfileAssetStore: SoundProfileAssetManaging {
    func bundledDefaultProfile() async -> SoundProfile {
        SoundProfile.bundledDefault(duration: 1)
    }

    func importSoundFiles(from urls: [URL]) async -> SoundProfileImportBatch {
        SoundProfileImportBatch(importedProfiles: [], failures: [])
    }

    func deleteImportedSoundProfile(_ profile: SoundProfile) async throws -> SoundProfileDeletionResult {
        .deleted
    }

    func url(for profile: SoundProfile) async throws -> URL {
        URL(fileURLWithPath: "/tmp/\(profile.id).wav")
    }
}

@MainActor
private final class SnapshotStubSoundProfilePreviewPlayer: SoundProfilePreviewPlaying {
    func playPreview(of soundProfile: SoundProfile) async throws {}
    func stopPreview() async {}
}

@MainActor
private final class SnapshotStubReminderAudioEngine: ReminderAudioEngine {
    func warmUp() async throws {}
    func defaultSoundDuration() async throws -> TimeInterval { 1 }
    func playDefaultSound() async throws {}
    func stopPlayback() async {}
}

@MainActor
private final class SnapshotStubAudioOutputRouteProvider: AudioOutputRouteProviding {
    func currentRoute() -> AudioOutputRouteSnapshot {
        AudioOutputRouteSnapshot(name: "Test Headphones", kind: .privateListening)
    }
}

@MainActor
private final class SnapshotStubReminderScheduler: ReminderScheduling {
    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> any ReminderScheduledTask {
        SnapshotStubReminderScheduledTask()
    }
}

@MainActor
private final class SnapshotStubReminderScheduledTask: ReminderScheduledTask {
    var isCancelled: Bool = false
    func cancel() { isCancelled = true }
}
