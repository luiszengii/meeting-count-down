import Foundation
import XCTest
@testable import FeishuMeetingCountdown

/// 这些测试验证 Phase 0 聚合层的主状态流是否稳定。
@MainActor
final class SourceCoordinatorTests: XCTestCase {
    /// 验证刷新成功后，协调层会更新最近刷新时间，并重新计算下一场会议。
    func testRefreshUpdatesLastRefreshAndNextMeeting() async {
        let now = fixedNow()
        let coordinator = SourceCoordinator(
            activeMode: .caldavSystemCalendar,
            sources: [
                .caldavSystemCalendar: StubMeetingSource(
                    descriptor: descriptor(for: .caldavSystemCalendar),
                    currentHealthState: .ready(message: "系统日历已接入"),
                    sampleMeetings: [
                        meeting(id: "later", mode: .caldavSystemCalendar, now: now, offsetMinutes: 45),
                        meeting(id: "sooner", mode: .caldavSystemCalendar, now: now, offsetMinutes: 15)
                    ]
                )
            ],
            nextMeetingSelector: DefaultNextMeetingSelector(),
            dateProvider: FixedDateProvider(currentDate: now),
            logger: AppLogger(source: "SourceCoordinatorTests"),
            autoRefreshOnStart: false
        )

        await coordinator.refresh(trigger: .manualRefresh)

        XCTAssertEqual(coordinator.state.lastRefreshAt, now)
        XCTAssertEqual(coordinator.state.nextMeeting?.id, "sooner")
        XCTAssertEqual(coordinator.state.healthState, .ready(message: "系统日历已接入"))
    }

    /// 验证切换活动模式时，会切换到新源并基于新源快照重算状态。
    func testActivateModeSwitchesToNewSourceAndRecomputesState() async {
        let now = fixedNow()
        let coordinator = SourceCoordinator(
            activeMode: .caldavSystemCalendar,
            sources: [
                .caldavSystemCalendar: StubMeetingSource(
                    descriptor: descriptor(for: .caldavSystemCalendar),
                    currentHealthState: .ready(message: "系统日历已接入"),
                    sampleMeetings: [meeting(id: "calendar", mode: .caldavSystemCalendar, now: now, offsetMinutes: 40)]
                ),
                .offlineImport: StubMeetingSource(
                    descriptor: descriptor(for: .offlineImport),
                    currentHealthState: .warning(message: "当前是离线快照"),
                    sampleMeetings: [meeting(id: "imported", mode: .offlineImport, now: now, offsetMinutes: 10)]
                )
            ],
            nextMeetingSelector: DefaultNextMeetingSelector(),
            dateProvider: FixedDateProvider(currentDate: now),
            logger: AppLogger(source: "SourceCoordinatorTests"),
            autoRefreshOnStart: false
        )

        await coordinator.activate(mode: .offlineImport)

        XCTAssertEqual(coordinator.state.activeMode, .offlineImport)
        XCTAssertEqual(coordinator.state.nextMeeting?.id, "imported")
        XCTAssertEqual(coordinator.state.healthState, .warning(message: "当前是离线快照"))
    }

    /// 验证底层源抛出可预期领域错误时，协调层会把状态标记为失败并清空会议结果。
    func testRefreshFailureMarksStateAsFailed() async {
        let now = fixedNow()
        let coordinator = SourceCoordinator(
            activeMode: .byoFeishuApp,
            sources: [
                .byoFeishuApp: FailingMeetingSource(
                    descriptor: descriptor(for: .byoFeishuApp),
                    error: .notConfigured(message: "缺少 App ID 和 App Secret")
                )
            ],
            nextMeetingSelector: DefaultNextMeetingSelector(),
            dateProvider: FixedDateProvider(currentDate: now),
            logger: AppLogger(source: "SourceCoordinatorTests"),
            autoRefreshOnStart: false
        )

        await coordinator.refresh(trigger: .manualRefresh)

        XCTAssertEqual(coordinator.state.healthState, .failed(message: "缺少 App ID 和 App Secret"))
        XCTAssertEqual(coordinator.state.lastErrorMessage, "缺少 App ID 和 App Secret")
        XCTAssertNil(coordinator.state.nextMeeting)
    }

    /// 统一生成测试用源描述符，避免每个测试都重复拼接样板字段。
    private func descriptor(for mode: ConnectionMode) -> MeetingSourceDescriptor {
        MeetingSourceDescriptor(
            mode: mode,
            sourceIdentifier: "test-\(mode.rawValue)",
            displayName: mode.displayName
        )
    }

    /// 构造在固定时间基础上偏移若干分钟的测试会议。
    private func meeting(id: String, mode: ConnectionMode, now: Date, offsetMinutes: Int) -> MeetingRecord {
        let startAt = Calendar(identifier: .gregorian).date(byAdding: .minute, value: offsetMinutes, to: now)!
        let endAt = Calendar(identifier: .gregorian).date(byAdding: .minute, value: 30, to: startAt)!

        return MeetingRecord(
            id: id,
            title: "Meeting \(id)",
            startAt: startAt,
            endAt: endAt,
            source: descriptor(for: mode)
        )
    }

    /// 返回所有测试共用的固定当前时间，确保断言稳定。
    private func fixedNow() -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 9, minute: 0))!
    }
}

/// 固定时钟实现，用于让测试里的“当前时间”完全可控。
private struct FixedDateProvider: DateProviding {
    /// 测试时注入的固定当前时间。
    let currentDate: Date

    /// 直接返回注入的固定时间。
    func now() -> Date {
        currentDate
    }
}

/// 故意失败的数据源实现，用于验证协调层错误处理路径。
private struct FailingMeetingSource: MeetingSource {
    /// 这个失败源也需要暴露来源描述，方便协调层照常记录模式信息。
    let descriptor: MeetingSourceDescriptor
    /// 预设要抛出的领域错误。
    let error: MeetingSourceError

    /// 失败源的健康状态直接映射到失败。
    func healthState() async -> SourceHealthState {
        .failed(message: error.userFacingMessage)
    }

    /// 每次刷新都抛出预设错误，便于稳定触发失败路径。
    func refresh(trigger: RefreshTrigger, now: Date) async throws -> SourceSyncSnapshot {
        throw error
    }
}
