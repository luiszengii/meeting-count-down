import AppKit
import SnapshotTesting
import SwiftUI
import XCTest
@testable import FeishuMeetingCountdown

/// 对 MenuBarContentView 做视觉基线快照，覆盖三种代表性状态：
/// 1. 空闲态：无即将开始的会议，日历已就绪
/// 2. 有会议且距离开始 25 分钟（进入"meetingSoon"预热胶囊态）
/// 3. 错误态：数据源无法读取
///
/// 亮色模式已足够代表 popover 视觉——popover 本身宽度固定（324pt），较小。
/// NSStatusItem 本身属于 AppKit 层，不在快照范围内（见 ADR）。
@MainActor
final class MenuBarContentViewSnapshotTests: XCTestCase {

    // MARK: - Constants

    /// MenuBarContentView 内部固定宽度为 324pt，高度根据内容自适应；
    /// 这里给一个合理的固定高度覆盖典型内容。
    private static let snapshotSize = CGSize(width: 360, height: 420)

    // MARK: - Snapshot helper

    /// SnapshotTesting 在 Swift 6 + xcodebuild 环境下 `#file` 可能产生相对路径，
    /// 导致无法在正确位置创建 `__Snapshots__` 目录。
    /// 通过显式传入 `snapshotDirectory` 解决此问题。
    private static let snapshotDirectory: String = {
        let filePath = #filePath
        if filePath.hasPrefix("/") {
            let dir = (filePath as NSString).deletingLastPathComponent
            return "\(dir)/__Snapshots__/MenuBarContentViewSnapshotTests"
        }
        return "/Users/luiszeng/Documents/GitHub/meeting-count-down/MeetingCountdownAppTests/Snapshots/__Snapshots__/MenuBarContentViewSnapshotTests"
    }()

    /// 使用 `verifySnapshot` 而不是 `assertSnapshot`，以便显式传入 `snapshotDirectory`
    /// 解决 Swift 6 + xcodebuild 下 `#filePath` 可能为相对路径的问题。
    private func assertMenuBarSnapshot(
        _ view: MenuBarContentView,
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

    // MARK: - Factories

    private func fixedNow() -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(
            year: 2026, month: 4, day: 23, hour: 10, minute: 0
        ))!
    }

    /// 空闲态：就绪、无即将会议。
    private func makeIdleComponents() -> (SourceCoordinator, ReminderPreferencesController, MenuBarPresentationClock) {
        let store = InMemoryPreferencesStore()
        let coordinator = SourceCoordinator(
            source: StubMeetingSource(
                descriptor: MeetingSourceDescriptor(
                    sourceIdentifier: "mb-snapshot-idle",
                    displayName: "CalDAV"
                ),
                currentHealthState: .ready(message: "ok"),
                sampleMeetings: []
            ),
            nextMeetingSelector: DefaultNextMeetingSelector(),
            preferencesStore: store,
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            logger: AppLogger(source: "MenuBarSnapshotTests"),
            autoRefreshOnStart: false
        )
        let reminderPrefs = ReminderPreferencesController(
            preferencesStore: store,
            autoRefreshOnStart: false
        )
        let clock = MenuBarPresentationClock(initialNow: fixedNow())
        return (coordinator, reminderPrefs, clock)
    }

    /// 有会议态：距离开始 25 分钟（进入预热胶囊范围）。
    private func makeUpcomingMeetingComponents() -> (SourceCoordinator, ReminderPreferencesController, MenuBarPresentationClock) {
        let store = InMemoryPreferencesStore()
        let meetingStartAt = fixedNow().addingTimeInterval(25 * 60) // 25 分钟后
        let coordinator = SourceCoordinator(
            source: StubMeetingSource(
                descriptor: MeetingSourceDescriptor(
                    sourceIdentifier: "mb-snapshot-meeting",
                    displayName: "CalDAV"
                ),
                currentHealthState: .ready(message: "ok"),
                sampleMeetings: [
                    MeetingRecord(
                        id: "snapshot-meeting-1",
                        title: "产品周会 · Q2 规划",
                        startAt: meetingStartAt,
                        endAt: meetingStartAt.addingTimeInterval(60 * 60),
                        links: [
                            MeetingLink(kind: .vc, url: URL(string: "https://example.feishu.cn/meet/abc123")!)
                        ],
                        source: MeetingSourceDescriptor(sourceIdentifier: "mb-snapshot-meeting", displayName: "CalDAV")
                    )
                ]
            ),
            nextMeetingSelector: DefaultNextMeetingSelector(),
            preferencesStore: store,
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            logger: AppLogger(source: "MenuBarSnapshotTests"),
            autoRefreshOnStart: false
        )
        let reminderPrefs = ReminderPreferencesController(
            preferencesStore: store,
            autoRefreshOnStart: false
        )
        let clock = MenuBarPresentationClock(initialNow: fixedNow())
        return (coordinator, reminderPrefs, clock)
    }

    /// 错误态：数据源读取失败。
    private func makeErrorComponents() -> (SourceCoordinator, ReminderPreferencesController, MenuBarPresentationClock) {
        let store = InMemoryPreferencesStore()
        let coordinator = SourceCoordinator(
            source: StubMeetingSource(
                descriptor: MeetingSourceDescriptor(
                    sourceIdentifier: "mb-snapshot-error",
                    displayName: "CalDAV"
                ),
                currentHealthState: .failed(message: "无法连接到 CalDAV 服务器"),
                sampleMeetings: []
            ),
            nextMeetingSelector: DefaultNextMeetingSelector(),
            preferencesStore: store,
            dateProvider: FixedDateProvider(currentDate: fixedNow()),
            logger: AppLogger(source: "MenuBarSnapshotTests"),
            autoRefreshOnStart: false
        )
        let reminderPrefs = ReminderPreferencesController(
            preferencesStore: store,
            autoRefreshOnStart: false
        )
        let clock = MenuBarPresentationClock(initialNow: fixedNow())
        return (coordinator, reminderPrefs, clock)
    }

    // MARK: - 1. Idle state (no upcoming meetings, source is ready)

    func testMenuBarIdleStateLight() async {
        let (coordinator, reminderPrefs, clock) = makeIdleComponents()
        // 触发一次刷新让协调层进入 .ready 状态（StubMeetingSource 没有 sampleMeetings）
        await coordinator.refresh(trigger: .appLaunch)
        let view = MenuBarContentView(
            sourceCoordinator: coordinator,
            reminderPreferencesController: reminderPrefs,
            menuBarPresentationClock: clock,
            openSettingsAction: {}
        )
        assertMenuBarSnapshot(view, appearance: NSAppearance(named: .aqua)!, named: "light")
    }

    // MARK: - 2. Upcoming meeting state (meeting starts in 25 min)

    func testMenuBarUpcomingMeetingLight() async {
        let (coordinator, reminderPrefs, clock) = makeUpcomingMeetingComponents()
        // 刷新后协调层会从 StubMeetingSource 取到 sampleMeetings 中的会议
        await coordinator.refresh(trigger: .appLaunch)
        let view = MenuBarContentView(
            sourceCoordinator: coordinator,
            reminderPreferencesController: reminderPrefs,
            menuBarPresentationClock: clock,
            openSettingsAction: {}
        )
        assertMenuBarSnapshot(view, appearance: NSAppearance(named: .aqua)!, named: "light")
    }

    // MARK: - 3. Error state (source failed to read)

    func testMenuBarErrorStateLight() async {
        let (coordinator, reminderPrefs, clock) = makeErrorComponents()
        // 刷新后协调层会进入 .failed 状态
        await coordinator.refresh(trigger: .appLaunch)
        let view = MenuBarContentView(
            sourceCoordinator: coordinator,
            reminderPreferencesController: reminderPrefs,
            menuBarPresentationClock: clock,
            openSettingsAction: {}
        )
        assertMenuBarSnapshot(view, appearance: NSAppearance(named: .aqua)!, named: "light")
    }
}
