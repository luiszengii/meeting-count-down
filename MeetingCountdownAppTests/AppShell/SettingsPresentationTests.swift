import Foundation
import XCTest
@testable import FeishuMeetingCountdown

/// 这些测试锁定设置页展示态里本轮最关键的信息架构收口规则。
/// 它们不验证 SwiftUI 具体排版，而是验证“哪些事实应该继续暴露，哪些不该再回流成全局复读”。
@MainActor
final class SettingsPresentationTests: XCTestCase {
    /// 概览页头部只应保留“整体状态 + 最近同步”两枚高层 badge，
    /// 避免把连接、授权等次级事实再塞回 hero 区。
    func testOverviewHeaderBadgesCollapseToHealthAndSyncOnly() async {
        let view = await makeSettingsView(
            authorizationState: .authorized,
            calendars: [calendar(id: "feishu", title: "飞书日历", suggested: true)]
        )

        XCTAssertEqual(view.overviewHeaderBadges.count, 2)
    }

    /// 当系统还没有授予日历读取权限时，高级页诊断摘要应直接指出权限问题，
    /// 而不是继续暴露难懂的内部 debug label。
    func testCalendarConnectionDiagnosticSummaryPrefersAuthorizationIssue() async {
        let view = await makeSettingsView(authorizationState: .denied)

        XCTAssertEqual(view.localizedCalendarConnectionDiagnosticSummary, "日历权限被拒绝")
    }

    /// 当用户以前保存过的日历已经不在当前系统列表里时，
    /// 高级页应显示用户化的诊断摘要，而不是直接把 `selectionDebugState` 原样露出来。
    func testCalendarConnectionDiagnosticSummaryUsesUserFacingSelectionMismatchCopy() async {
        let view = await makeSettingsView(
            authorizationState: .authorized,
            calendars: [calendar(id: "current", title: "当前日历", suggested: false)],
            storedSelectedCalendarIDs: ["missing"],
            hasStoredSelection: true
        )

        XCTAssertEqual(view.localizedCalendarConnectionDiagnosticSummary, "已保存的日历当前不可用")
    }

    /// 为展示态测试统一构造一份最小可用的设置页依赖，避免每个用例都重复装配控制器。
    private func makeSettingsView(
        authorizationState: SystemCalendarAuthorizationState,
        calendars: [SystemCalendarDescriptor] = [],
        storedSelectedCalendarIDs: Set<String> = [],
        hasStoredSelection: Bool = false
    ) async -> SettingsView {
        let preferencesStore = InMemoryPreferencesStore(
            selectedSystemCalendarIDs: storedSelectedCalendarIDs,
            hasStoredSelectedSystemCalendarIDs: hasStoredSelection
        )
        let sourceCoordinator = SourceCoordinator(
            source: StubMeetingSource(
                descriptor: MeetingSourceDescriptor(
                    sourceIdentifier: "test-system-calendar",
                    displayName: "CalDAV / 系统日历"
                ),
                currentHealthState: .ready(message: "系统日历已接入"),
                sampleMeetings: []
            ),
            nextMeetingSelector: DefaultNextMeetingSelector(),
            preferencesStore: preferencesStore,
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            logger: AppLogger(source: "SettingsPresentationTests"),
            autoRefreshOnStart: false
        )
        let systemCalendarConnectionController = SystemCalendarConnectionController(
            calendarAccess: StubSystemCalendarAccess(
                authorizationState: authorizationState,
                calendars: calendars
            ),
            preferencesStore: preferencesStore,
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            autoRefreshOnStart: false
        )
        let reminderPreferencesController = ReminderPreferencesController(
            preferencesStore: preferencesStore,
            autoRefreshOnStart: false
        )
        let soundProfileLibraryController = SoundProfileLibraryController(
            preferencesStore: preferencesStore,
            assetStore: SettingsPresentationStubSoundProfileAssetStore(),
            previewPlayer: SettingsPresentationStubSoundProfilePreviewPlayer(),
            autoRefreshOnStart: false
        )
        let reminderEngine = ReminderEngine(
            preferencesStore: preferencesStore,
            audioEngine: StubReminderAudioEngine(),
            audioOutputRouteProvider: StubAudioOutputRouteProvider(),
            scheduler: StubReminderScheduler(),
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            logger: AppLogger(source: "SettingsPresentationTests")
        )
        let launchAtLoginController = LaunchAtLoginController(autoRefreshOnStart: false)

        await systemCalendarConnectionController.refreshState()

        return SettingsView(
            sourceCoordinator: sourceCoordinator,
            systemCalendarConnectionController: systemCalendarConnectionController,
            reminderEngine: reminderEngine,
            reminderPreferencesController: reminderPreferencesController,
            soundProfileLibraryController: soundProfileLibraryController,
            launchAtLoginController: launchAtLoginController
        )
    }

    /// 统一生成测试日历描述符，避免每个用例重复拼接样板字段。
    private func calendar(id: String, title: String, suggested: Bool) -> SystemCalendarDescriptor {
        SystemCalendarDescriptor(
            id: id,
            title: title,
            sourceTitle: "测试账户",
            sourceTypeLabel: "CalDAV",
            isSuggestedByDefault: suggested
        )
    }

    /// 这些展示态测试共用同一个固定当前时间，避免日期相关文案受真实时钟影响。
    private func fixedNow() -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 4, day: 14, hour: 14, minute: 0))!
    }
}

/// 固定时钟让设置页展示态里的“上次同步 / 下一场会议”类文案更稳定。
private struct FixedDateProvider: DateProviding {
    let currentDate: Date

    func now() -> Date {
        currentDate
    }
}

/// 这里用纯 Swift stub 替掉真实 EventKit 访问层，避免设置页展示测试依赖宿主机器权限。
@MainActor
private final class StubSystemCalendarAccess: SystemCalendarAccessing {
    let authorizationState: SystemCalendarAuthorizationState
    let calendars: [SystemCalendarDescriptor]

    init(
        authorizationState: SystemCalendarAuthorizationState,
        calendars: [SystemCalendarDescriptor]
    ) {
        self.authorizationState = authorizationState
        self.calendars = calendars
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
        []
    }
}

/// 展示态测试不关心真实音频文件，因此资产存储层只返回最小可用的默认音频。
private actor SettingsPresentationStubSoundProfileAssetStore: SoundProfileAssetManaging {
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

/// 试听播放器在这些测试里不会真的被调用，因此保留空实现即可。
@MainActor
private final class SettingsPresentationStubSoundProfilePreviewPlayer: SoundProfilePreviewPlaying {
    func playPreview(of soundProfile: SoundProfile) async throws {}

    func stopPreview() async {}
}

/// 提醒引擎展示态只需要一份稳定的默认音频时长，不需要真实播放能力。
@MainActor
private final class StubReminderAudioEngine: ReminderAudioEngine {
    func warmUp() async throws {}

    func defaultSoundDuration() async throws -> TimeInterval {
        1
    }

    func playDefaultSound() async throws {}

    func stopPlayback() async {}
}

/// 展示态测试不需要真实输出设备探测，因此固定返回一个可读的耳机场景即可。
@MainActor
private final class StubAudioOutputRouteProvider: AudioOutputRouteProviding {
    func currentRoute() -> AudioOutputRouteSnapshot {
        AudioOutputRouteSnapshot(name: "Test Headphones", kind: .privateListening)
    }
}

/// 提醒调度器在这些测试里不会真的创建任务，但仍需要满足引擎初始化依赖。
@MainActor
private final class StubReminderScheduler: ReminderScheduling {
    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> any ReminderScheduledTask {
        StubReminderScheduledTask()
    }
}

/// 空调度句柄只负责满足协议，不承担真实延迟任务。
@MainActor
private final class StubReminderScheduledTask: ReminderScheduledTask {
    var isCancelled: Bool = false

    func cancel() {
        isCancelled = true
    }
}
