import Foundation
import XCTest
@testable import FeishuMeetingCountdown

/// 这些测试验证 Phase 4 本地提醒引擎最核心的调度和去重规则。
@MainActor
final class ReminderEngineTests: XCTestCase {
    /// 验证未来会议会被换算成一条真正的延迟提醒任务，而不是立刻播放。
    func testReconcileSchedulesFutureMeetingUsingDefaultSoundDuration() async {
        let now = fixedNow()
        let audioEngine = SpyReminderAudioEngine(defaultDuration: 4)
        let scheduler = TestReminderScheduler()
        let engine = makeEngine(
            now: now,
            audioEngine: audioEngine,
            scheduler: scheduler
        )

        await engine.reconcile(with: readyState(nextMeeting: meeting(id: "future", now: now, offsetSeconds: 300)))

        guard case let .scheduled(context) = engine.state else {
            return XCTFail("Expected scheduled state, got \(engine.state)")
        }

        XCTAssertEqual(context.countdownSeconds, 4)
        XCTAssertEqual(context.triggerAt, now.addingTimeInterval(296))
        XCTAssertEqual(scheduler.activeTasks.count, 1)
        guard let scheduledTask = scheduler.activeTasks.first else {
            return XCTFail("Expected one scheduled reminder task")
        }
        XCTAssertEqual(scheduledTask.delay, 296, accuracy: 0.001)
        XCTAssertEqual(audioEngine.playCallCount, 0)

        await engine.stopAll()
    }

    /// 验证等价的下一场会议重复发布时，会复用已有提醒而不是先取消再重建一条新任务。
    func testReconcileReusesEquivalentScheduledReminderInsteadOfRescheduling() async {
        let now = fixedNow()
        let audioEngine = SpyReminderAudioEngine(defaultDuration: 4)
        let scheduler = TestReminderScheduler()
        let engine = makeEngine(
            now: now,
            audioEngine: audioEngine,
            scheduler: scheduler
        )
        let sourceState = readyState(nextMeeting: meeting(id: "same", now: now, offsetSeconds: 300))

        await engine.reconcile(with: sourceState)
        let firstTask = try? XCTUnwrap(scheduler.activeTasks.first)

        await engine.reconcile(with: sourceState)

        XCTAssertEqual(scheduler.tasks.count, 1)
        XCTAssertEqual(scheduler.activeTasks.count, 1)
        XCTAssertFalse(firstTask?.isCancelled ?? true)
        guard case let .scheduled(context) = engine.state else {
            return XCTFail("Expected scheduled state after equivalent reconcile, got \(engine.state)")
        }
        XCTAssertEqual(context.meeting.id, "same")
        XCTAssertEqual(audioEngine.playCallCount, 0)

        await engine.stopAll()
    }

    /// 验证当会议已经近到来不及等待完整倒计时时，会立即触发默认音效播放。
    func testReconcileImmediatelyPlaysWhenMeetingIsInsideCountdownWindow() async {
        let now = fixedNow()
        let audioEngine = SpyReminderAudioEngine(defaultDuration: 120)
        let scheduler = TestReminderScheduler()
        let engine = makeEngine(
            now: now,
            audioEngine: audioEngine,
            scheduler: scheduler
        )

        await engine.reconcile(with: readyState(nextMeeting: meeting(id: "soon", now: now, offsetSeconds: 30)))

        guard case let .playing(context, _) = engine.state else {
            return XCTFail("Expected playing state, got \(engine.state)")
        }

        XCTAssertTrue(context.triggeredImmediately)
        XCTAssertEqual(audioEngine.playCallCount, 1)
        XCTAssertEqual(scheduler.activeTasks.count, 1)
        guard let playbackTask = scheduler.activeTasks.first else {
            return XCTFail("Expected one playback completion task")
        }
        XCTAssertEqual(playbackTask.delay, 120, accuracy: 0.001)
    }

    /// 验证静音模式仍然会命中提醒，但不会真的调用音频播放。
    func testReconcileTriggersSilentlyWhenMuted() async {
        let now = fixedNow()
        let audioEngine = SpyReminderAudioEngine(defaultDuration: 120)
        let scheduler = TestReminderScheduler()
        let engine = makeEngine(
            now: now,
            audioEngine: audioEngine,
            scheduler: scheduler,
            reminderPreferences: ReminderPreferences(
                isMuted: true,
                interfaceLanguage: .simplifiedChinese
            )
        )

        await engine.reconcile(with: readyState(nextMeeting: meeting(id: "muted", now: now, offsetSeconds: 30)))

        guard case let .triggeredSilently(context, _, reason) = engine.state else {
            return XCTFail("Expected silent trigger state, got \(engine.state)")
        }

        XCTAssertTrue(context.triggeredImmediately)
        XCTAssertEqual(reason, .userMuted)
        XCTAssertEqual(audioEngine.playCallCount, 0)
        XCTAssertTrue(scheduler.activeTasks.isEmpty)
    }

    /// 验证开启“仅耳机输出时播放”后，如果默认输出是外放，则会静默命中而不是播放音频。
    func testReconcileTriggersSilentlyWhenHeadphonePolicyBlocksCurrentOutput() async {
        let now = fixedNow()
        let audioEngine = SpyReminderAudioEngine(defaultDuration: 120)
        let scheduler = TestReminderScheduler()
        let routeProvider = StubAudioOutputRouteProvider(
            route: AudioOutputRouteSnapshot(name: "MacBook Pro Speakers", kind: .speakerLike)
        )
        let engine = makeEngine(
            now: now,
            audioEngine: audioEngine,
            scheduler: scheduler,
            audioOutputRouteProvider: routeProvider,
            reminderPreferences: ReminderPreferences(
                playSoundOnlyWhenHeadphonesConnected: true,
                interfaceLanguage: .simplifiedChinese
            )
        )

        await engine.reconcile(with: readyState(nextMeeting: meeting(id: "speaker", now: now, offsetSeconds: 30)))

        guard case let .triggeredSilently(context, _, reason) = engine.state else {
            return XCTFail("Expected silent trigger state, got \(engine.state)")
        }

        XCTAssertTrue(context.triggeredImmediately)
        XCTAssertEqual(reason, .outputRoutePolicy(routeName: "MacBook Pro Speakers"))
        XCTAssertEqual(audioEngine.playCallCount, 0)
    }

    /// 验证关闭总提醒开关后，不会创建任何活动提醒任务。
    func testReconcileStaysDisabledWhenGlobalReminderIsOff() async {
        let now = fixedNow()
        let audioEngine = SpyReminderAudioEngine(defaultDuration: 5)
        let scheduler = TestReminderScheduler()
        let engine = makeEngine(
            now: now,
            audioEngine: audioEngine,
            scheduler: scheduler,
            reminderPreferences: ReminderPreferences(
                globalReminderEnabled: false,
                interfaceLanguage: .simplifiedChinese
            )
        )

        await engine.reconcile(with: readyState(nextMeeting: meeting(id: "off", now: now, offsetSeconds: 300)))

        XCTAssertEqual(engine.state, .disabled)
        XCTAssertTrue(scheduler.activeTasks.isEmpty)
        XCTAssertEqual(audioEngine.playCallCount, 0)
    }

    /// 验证同一场会议在提醒已经完整触发结束后，不会在下一次重算时再次播放提醒。
    func testReconcileDoesNotReplayAlreadyTriggeredMeetingAfterPlaybackCompleted() async {
        let now = fixedNow()
        let audioEngine = SpyReminderAudioEngine(defaultDuration: 120)
        let scheduler = TestReminderScheduler()
        let engine = makeEngine(
            now: now,
            audioEngine: audioEngine,
            scheduler: scheduler
        )
        let sourceState = readyState(nextMeeting: meeting(id: "dedupe", now: now, offsetSeconds: 30))

        await engine.reconcile(with: sourceState)
        XCTAssertEqual(audioEngine.playCallCount, 1)

        await scheduler.fireNextActiveTask()

        await engine.reconcile(with: sourceState)

        XCTAssertEqual(audioEngine.playCallCount, 1)
        guard case let .idle(message) = engine.state else {
            return XCTFail("Expected idle state after duplicate reconcile, got \(engine.state)")
        }
        XCTAssertTrue(message.contains("提醒已触发"))
    }

    /// 验证当下一场会议消失后，之前已经安排好的延迟任务会被取消。
    func testReconcileCancelsScheduledTaskWhenNextMeetingDisappears() async {
        let now = fixedNow()
        let audioEngine = SpyReminderAudioEngine(defaultDuration: 10)
        let scheduler = TestReminderScheduler()
        let engine = makeEngine(
            now: now,
            audioEngine: audioEngine,
            scheduler: scheduler
        )

        await engine.reconcile(with: readyState(nextMeeting: meeting(id: "cancel", now: now, offsetSeconds: 300)))
        let scheduledTask = try? XCTUnwrap(scheduler.activeTasks.first)

        await engine.reconcile(with: readyState(nextMeeting: nil))

        XCTAssertTrue(scheduledTask?.isCancelled ?? false)
        guard case let .idle(message) = engine.state else {
            return XCTFail("Expected idle state after removing meeting, got \(engine.state)")
        }
        XCTAssertTrue(message.contains("没有可安排提醒"))
    }

    /// 验证默认音效播放完成后，提醒状态会回到“已触发，等待下一场会议”。
    func testPlaybackCompletionReturnsStateToIdle() async {
        let now = fixedNow()
        let audioEngine = SpyReminderAudioEngine(defaultDuration: 2)
        let scheduler = TestReminderScheduler()
        let engine = makeEngine(
            now: now,
            audioEngine: audioEngine,
            scheduler: scheduler
        )

        await engine.reconcile(with: readyState(nextMeeting: meeting(id: "playback", now: now, offsetSeconds: 1)))
        XCTAssertEqual(audioEngine.playCallCount, 1)

        await scheduler.fireNextActiveTask()

        guard case let .idle(message) = engine.state else {
            return XCTFail("Expected idle state after playback completion, got \(engine.state)")
        }
        XCTAssertTrue(message.contains("提醒已触发"))
    }

    /// 验证会前倒计时进行中时，菜单栏会切到秒级倒计时标签。
    func testPlayingStateProvidesMenuBarAlertPresentation() {
        let now = fixedNow()
        let context = ScheduledReminderContext(
            meeting: meeting(id: "menu-bar-playing", now: now, offsetSeconds: 10),
            triggerAt: now,
            countdownSeconds: 4,
            triggeredImmediately: true
        )
        let state = ReminderState.playing(context: context, startedAt: now)

        XCTAssertEqual(
            state.menuBarAlertPresentation(at: now),
            ReminderMenuBarAlertPresentation(
                title: "10s",
                symbolName: "timer.circle.fill",
                isHighPriority: true,
                showsCapsuleBackground: true,
                shouldHighlightRed: true
            )
        )
    }

    /// 验证静音命中时，菜单栏仍会切到单独的静音提醒标签。
    func testTriggeredSilentlyStateProvidesMenuBarAlertPresentation() {
        let now = fixedNow()
        let context = ScheduledReminderContext(
            meeting: meeting(id: "menu-bar-silent", now: now, offsetSeconds: 30),
            triggerAt: now,
            countdownSeconds: 4,
            triggeredImmediately: true
        )
        let state = ReminderState.triggeredSilently(
            context: context,
            triggeredAt: now,
            reason: .userMuted
        )

        XCTAssertEqual(
            state.menuBarAlertPresentation(at: now),
            ReminderMenuBarAlertPresentation(
                title: "静音开会",
                symbolName: "bell.slash.circle.fill",
                isHighPriority: true,
                showsCapsuleBackground: true,
                shouldHighlightRed: false
            )
        )
    }

    /// 验证因耳机输出策略被拦截时，菜单栏会切到单独的“避免外放”提醒标签。
    func testTriggeredSilentlyByOutputPolicyProvidesDedicatedMenuBarAlertPresentation() {
        let now = fixedNow()
        let context = ScheduledReminderContext(
            meeting: meeting(id: "menu-bar-speaker", now: now, offsetSeconds: 30),
            triggerAt: now,
            countdownSeconds: 4,
            triggeredImmediately: true
        )
        let state = ReminderState.triggeredSilently(
            context: context,
            triggeredAt: now,
            reason: .outputRoutePolicy(routeName: "MacBook Pro Speakers")
        )

        XCTAssertEqual(
            state.menuBarAlertPresentation(at: now),
            ReminderMenuBarAlertPresentation(
                title: "避免外放",
                symbolName: "speaker.slash.circle.fill",
                isHighPriority: true,
                showsCapsuleBackground: true,
                shouldHighlightRed: false
            )
        )
    }

    /// 验证普通待调度状态不会错误地把菜单栏切到提醒态。
    func testScheduledStateDoesNotProvideMenuBarAlertPresentation() {
        let now = fixedNow()
        let context = ScheduledReminderContext(
            meeting: meeting(id: "menu-bar-idle", now: now, offsetSeconds: 300),
            triggerAt: now.addingTimeInterval(296),
            countdownSeconds: 4,
            triggeredImmediately: false
        )
        let state = ReminderState.scheduled(context)

        XCTAssertNil(state.menuBarAlertPresentation(at: now))
    }

    /// 用统一入口构造提醒引擎，避免每个测试都重复拼接样板依赖。
    private func makeEngine(
        now: Date,
        audioEngine: SpyReminderAudioEngine,
        scheduler: TestReminderScheduler,
        audioOutputRouteProvider: any AudioOutputRouteProviding = StubAudioOutputRouteProvider(
            route: AudioOutputRouteSnapshot(name: "AirPods Pro", kind: .privateListening)
        ),
        reminderPreferences: ReminderPreferences = .default
    ) -> ReminderEngine {
        ReminderEngine(
            preferencesStore: InMemoryPreferencesStore(reminderPreferences: reminderPreferences),
            audioEngine: audioEngine,
            audioOutputRouteProvider: audioOutputRouteProvider,
            scheduler: scheduler,
            dateProvider: FixedDateProvider(currentDate: now),
            logger: AppLogger(source: "ReminderEngineTests")
        )
    }

    /// 构造一个最常见的就绪态源状态，供提醒引擎直接消费。
    private func readyState(nextMeeting: MeetingRecord?) -> SourceCoordinatorState {
        SourceCoordinatorState(
            healthState: .ready(message: "系统日历已接入"),
            lastRefreshAt: fixedNow(),
            nextMeeting: nextMeeting,
            meetings: nextMeeting.map { [$0] } ?? [],
            isRefreshing: false,
            lastErrorMessage: nil
        )
    }

    /// 构造在固定时间基础上偏移若干秒的测试会议。
    private func meeting(id: String, now: Date, offsetSeconds: Int) -> MeetingRecord {
        let startAt = now.addingTimeInterval(TimeInterval(offsetSeconds))
        let endAt = startAt.addingTimeInterval(30 * 60)

        return MeetingRecord(
            id: id,
            title: "Meeting \(id)",
            startAt: startAt,
            endAt: endAt,
            source: MeetingSourceDescriptor(
                sourceIdentifier: "test-system-calendar",
                displayName: "CalDAV / 系统日历"
            )
        )
    }

    /// 提供所有测试共享的固定当前时间，避免断言依赖真实时钟。
    private func fixedNow() -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 9, minute: 0, second: 0))!
    }
}

/// 用固定路由替代真实 CoreAudio 探测，让测试可以精确控制“当前默认输出设备”的语义。
@MainActor
private final class StubAudioOutputRouteProvider: AudioOutputRouteProviding {
    let route: AudioOutputRouteSnapshot

    init(route: AudioOutputRouteSnapshot) {
        self.route = route
    }

    func currentRoute() -> AudioOutputRouteSnapshot {
        route
    }
}

/// 用纯 Swift 假音频引擎替代真实 AVFoundation，实现稳定的调度断言。
@MainActor
private final class SpyReminderAudioEngine: ReminderAudioEngine {
    /// 当前假定的默认音效时长。
    let defaultDuration: TimeInterval
    /// 记录真正播放动作被触发了多少次。
    private(set) var playCallCount = 0
    /// 记录停止播放被调用了多少次，方便未来扩展取消测试。
    private(set) var stopCallCount = 0

    init(defaultDuration: TimeInterval) {
        self.defaultDuration = defaultDuration
    }

    func warmUp() async throws {
        /// 假实现不需要真正做任何事情，只保留和生产协议一致的入口。
    }

    func defaultSoundDuration() async throws -> TimeInterval {
        defaultDuration
    }

    func playDefaultSound() async throws {
        playCallCount += 1
    }

    func stopPlayback() async {
        stopCallCount += 1
    }
}

/// 用手动触发的假调度器代替真实 `Task.sleep`，避免测试真的等待时间流逝。
@MainActor
private final class TestReminderScheduler: ReminderScheduling {
    /// 单条假任务除了保存延迟，还要保存稍后要执行的异步动作。
    final class ScheduledTask: ReminderScheduledTask {
        /// 当前任务记录的目标延迟。
        let delay: TimeInterval
        /// 真正要在测试里手动触发的动作。
        let operation: @MainActor @Sendable () async -> Void
        /// 记录是否已经被取消。
        private(set) var isCancelled = false
        /// 记录是否已经被手动触发过一次，避免重复执行同一任务。
        private(set) var hasFired = false

        init(delay: TimeInterval, operation: @escaping @MainActor @Sendable () async -> Void) {
            self.delay = delay
            self.operation = operation
        }

        func cancel() {
            isCancelled = true
        }

        /// 让测试显式执行这条任务，而不是等待真实时间流逝。
        func fire() async {
            guard !isCancelled, !hasFired else {
                return
            }

            hasFired = true
            await operation()
        }
    }

    /// 当前测试过程中创建过的所有任务。
    private(set) var tasks: [ScheduledTask] = []

    /// 按生产接口返回一条可取消任务，但内部只记录下来等待测试触发。
    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> any ReminderScheduledTask {
        let task = ScheduledTask(delay: delay, operation: operation)
        tasks.append(task)
        return task
    }

    /// 返回当前还处于活动状态的任务，方便测试检查取消和后续调度。
    var activeTasks: [ScheduledTask] {
        tasks.filter { !$0.isCancelled && !$0.hasFired }
    }

    /// 让测试手动触发当前第一条活动任务。
    func fireNextActiveTask() async {
        guard let nextTask = activeTasks.first else {
            return
        }

        await nextTask.fire()
    }
}
