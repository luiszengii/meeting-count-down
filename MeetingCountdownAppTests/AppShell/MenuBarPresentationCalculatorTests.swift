import Foundation
import XCTest
@testable import FeishuMeetingCountdown

/// 这些测试锁定 `MenuBarPresentationCalculator` 在各种 `ReminderState` 和
/// `SourceCoordinatorState` 组合下返回的 `MenuBarPresentation` 是否符合预期。
/// 测试全部使用固定的 `now` 时间点，避免时间依赖导致不稳定。
final class MenuBarPresentationCalculatorTests: XCTestCase {

    // MARK: - Fixed reference time

    /// 所有测试共用这个固定时间点，让闪烁逻辑和秒数计算都有确定性输出。
    private let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)

    // MARK: - 1. Idle state

    /// 验证提醒引擎空闲时，计算器输出空闲视觉态和简短健康标签。
    func testIdleReminderStateWithReadySourceProducesIdlePresentation() {
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: .idle(message: "当前没有活动提醒任务。"),
            sourceCoordinatorState: readyStateWithNoMeeting(),
            now: fixedNow,
            uiLanguage: .simplifiedChinese
        )

        XCTAssertEqual(presentation.visualState, .idle)
        XCTAssertFalse(presentation.showsCapsuleBackground)
        XCTAssertFalse(presentation.shouldHighlightRed)
        XCTAssertFalse(presentation.isHighPriority)
        XCTAssertEqual(presentation.title, "就绪")
    }

    /// 验证英文模式下空闲态标题正确本地化。
    func testIdleReminderStateInEnglishProducesEnglishTitle() {
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: .idle(message: "No active reminder."),
            sourceCoordinatorState: readyStateWithNoMeeting(),
            now: fixedNow,
            uiLanguage: .english
        )

        XCTAssertEqual(presentation.title, "Ready")
    }

    // MARK: - 2. Scheduled (future meeting)

    /// 验证已安排提醒且会议距离当前超过 30 分钟时，退回空闲视觉态并显示倒计时文案。
    func testScheduledReminderWithMeetingFarAwayProducesIdlePresentation() {
        let meetingStart = fixedNow.addingTimeInterval(90 * 60) // 90 分钟后
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: .scheduled(countdownContext(meetingStartAt: meetingStart, now: fixedNow)),
            sourceCoordinatorState: readyState(nextMeetingAt: meetingStart),
            now: fixedNow,
            uiLanguage: .simplifiedChinese
        )

        XCTAssertEqual(presentation.visualState, .idle)
        XCTAssertFalse(presentation.showsCapsuleBackground)
        // 90 分钟 = 1 小时 30 分钟
        XCTAssertEqual(presentation.title, "1 小时 30 分钟")
    }

    /// 验证已安排提醒且会议在 30 分钟内时，切换到预热胶囊态。
    func testScheduledReminderWithMeetingSoonProducesMeetingSoonPresentation() {
        let meetingStart = fixedNow.addingTimeInterval(15 * 60) // 15 分钟后
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: .scheduled(countdownContext(meetingStartAt: meetingStart, now: fixedNow)),
            sourceCoordinatorState: readyState(nextMeetingAt: meetingStart),
            now: fixedNow,
            uiLanguage: .simplifiedChinese
        )

        XCTAssertEqual(presentation.visualState, .meetingSoon)
        XCTAssertTrue(presentation.showsCapsuleBackground)
        XCTAssertFalse(presentation.shouldHighlightRed)
        XCTAssertEqual(presentation.title, "15 分钟")
    }

    /// 验证英文模式下预热胶囊态倒计时格式正确。
    func testScheduledReminderInEnglishProducesEnglishCountdown() {
        let meetingStart = fixedNow.addingTimeInterval(25 * 60)
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: .scheduled(countdownContext(meetingStartAt: meetingStart, now: fixedNow)),
            sourceCoordinatorState: readyState(nextMeetingAt: meetingStart),
            now: fixedNow,
            uiLanguage: .english
        )

        XCTAssertEqual(presentation.title, "25m")
    }

    // MARK: - 3. Playing (pre-start, remainingSeconds > 0)

    /// 验证播放型提醒在会前阶段时，输出紧急视觉态并显示倒计时秒数。
    func testPlayingWithPositiveRemainingSecondsProducesUrgentCountdownPresentation() {
        let meetingStart = fixedNow.addingTimeInterval(20)
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: .playing(
                context: countdownContext(meetingStartAt: meetingStart, now: fixedNow),
                startedAt: fixedNow
            ),
            sourceCoordinatorState: readyState(nextMeetingAt: meetingStart),
            now: fixedNow,
            uiLanguage: .simplifiedChinese
        )

        XCTAssertEqual(presentation.visualState, .urgent)
        XCTAssertTrue(presentation.showsCapsuleBackground)
        XCTAssertTrue(presentation.isHighPriority)
        XCTAssertEqual(presentation.title, "20s")
        XCTAssertEqual(presentation.symbolName, "timer.circle.fill")
    }

    // MARK: - 4. Playing (overdue, negative remaining)

    /// 验证播放型提醒在会议已经开始（负剩余时间）时，显示会议标题而不是秒数。
    func testPlayingWithNegativeRemainingSecondsShowsMeetingTitle() {
        let meetingStart = fixedNow.addingTimeInterval(-5) // 5 秒前已开始
        let context = countdownContext(meetingStartAt: meetingStart, now: fixedNow, meetingTitle: "周例会")
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: .playing(context: context, startedAt: fixedNow.addingTimeInterval(-10)),
            sourceCoordinatorState: readyState(nextMeetingAt: meetingStart),
            now: fixedNow,
            uiLanguage: .simplifiedChinese
        )

        XCTAssertEqual(presentation.visualState, .urgent)
        XCTAssertEqual(presentation.title, "周例会")
        XCTAssertEqual(presentation.symbolName, "exclamationmark.circle.fill")
        XCTAssertFalse(presentation.shouldHighlightRed)
    }

    // MARK: - 5. Failed

    /// 验证提醒链路失败时，输出空闲视觉态和健康标签（无会议）。
    func testFailedReminderStateWithNoMeetingProducesIdlePresentation() {
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: .failed(message: "准备提醒失败"),
            sourceCoordinatorState: readyStateWithNoMeeting(),
            now: fixedNow,
            uiLanguage: .simplifiedChinese
        )

        XCTAssertEqual(presentation.visualState, .idle)
        XCTAssertFalse(presentation.showsCapsuleBackground)
    }

    // MARK: - 6. Disabled

    /// 验证提醒总开关关闭时，计算器退回到源层的普通显示逻辑。
    func testDisabledReminderStateWithMeetingSoonProducesMeetingSoonPresentation() {
        let meetingStart = fixedNow.addingTimeInterval(10 * 60)
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: .disabled,
            sourceCoordinatorState: readyState(nextMeetingAt: meetingStart),
            now: fixedNow,
            uiLanguage: .simplifiedChinese
        )

        // disabled 没有 alertPresentation，所以退回到普通路径
        XCTAssertEqual(presentation.visualState, .meetingSoon)
        XCTAssertTrue(presentation.showsCapsuleBackground)
        XCTAssertFalse(presentation.shouldHighlightRed)
    }

    // MARK: - 7. Triggered silently (userMuted)

    /// 验证用户静音命中时，输出紧急视觉态并显示静音标签（中文）。
    func testTriggeredSilentlyByUserMuteProducesChineseMutedTitle() {
        let meetingStart = fixedNow.addingTimeInterval(5)
        let context = countdownContext(meetingStartAt: meetingStart, now: fixedNow)
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: .triggeredSilently(context: context, triggeredAt: fixedNow, reason: .userMuted),
            sourceCoordinatorState: readyState(nextMeetingAt: meetingStart),
            now: fixedNow,
            uiLanguage: .simplifiedChinese
        )

        XCTAssertEqual(presentation.visualState, .urgent)
        XCTAssertTrue(presentation.isHighPriority)
        XCTAssertEqual(presentation.title, "静音开会")
        XCTAssertEqual(presentation.symbolName, "bell.slash.circle.fill")
    }

    /// 验证用户静音命中时英文标题正确本地化。
    func testTriggeredSilentlyByUserMuteInEnglishProducesEnglishTitle() {
        let meetingStart = fixedNow.addingTimeInterval(5)
        let context = countdownContext(meetingStartAt: meetingStart, now: fixedNow)
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: .triggeredSilently(context: context, triggeredAt: fixedNow, reason: .userMuted),
            sourceCoordinatorState: readyState(nextMeetingAt: meetingStart),
            now: fixedNow,
            uiLanguage: .english
        )

        XCTAssertEqual(presentation.title, "Muted")
    }

    /// 验证因输出路由策略静默命中时，标题正确（中文）。
    func testTriggeredSilentlyByOutputPolicyProducesChinesePrivateAudioTitle() {
        let meetingStart = fixedNow.addingTimeInterval(5)
        let context = countdownContext(meetingStartAt: meetingStart, now: fixedNow)
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: .triggeredSilently(
                context: context,
                triggeredAt: fixedNow,
                reason: .outputRoutePolicy(routeName: "MacBook Pro Speakers")
            ),
            sourceCoordinatorState: readyState(nextMeetingAt: meetingStart),
            now: fixedNow,
            uiLanguage: .simplifiedChinese
        )

        XCTAssertEqual(presentation.title, "避免外放")
        XCTAssertEqual(presentation.symbolName, "speaker.slash.circle.fill")
    }

    /// 验证因输出路由策略静默命中时英文标题正确。
    func testTriggeredSilentlyByOutputPolicyInEnglishProducesEnglishTitle() {
        let meetingStart = fixedNow.addingTimeInterval(5)
        let context = countdownContext(meetingStartAt: meetingStart, now: fixedNow)
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: .triggeredSilently(
                context: context,
                triggeredAt: fixedNow,
                reason: .outputRoutePolicy(routeName: "MacBook Pro Speakers")
            ),
            sourceCoordinatorState: readyState(nextMeetingAt: meetingStart),
            now: fixedNow,
            uiLanguage: .english
        )

        XCTAssertEqual(presentation.title, "Private Audio")
    }

    // MARK: - Unconfigured / warning / failed health states

    /// 验证源层未配置时，标题正确（英文）。
    func testUnconfiguredSourceInEnglishProducesSetupTitle() {
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: .idle(message: "No reminder."),
            sourceCoordinatorState: unconfiguredState(),
            now: fixedNow,
            uiLanguage: .english
        )

        XCTAssertEqual(presentation.title, "Setup")
    }

    /// 验证源层失败时，标题正确（中文）。
    func testFailedSourceInChineseProducesFailedTitle() {
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: .idle(message: "No reminder."),
            sourceCoordinatorState: failedState(),
            now: fixedNow,
            uiLanguage: .simplifiedChinese
        )

        XCTAssertEqual(presentation.title, "失败")
    }

    // MARK: - Countdown format edge cases

    /// 验证距会议不足 60 秒时按秒粒度显示倒计时（不再统一收成"即将开始"），
    /// 让用户在提醒真正命中前也能看到菜单栏秒级倒计时。
    func testMeetingWithinOneMinuteShowsSecondsCountdown() {
        let meetingStart = fixedNow.addingTimeInterval(30)
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: .idle(message: "No reminder."),
            sourceCoordinatorState: readyState(nextMeetingAt: meetingStart),
            now: fixedNow,
            uiLanguage: .simplifiedChinese
        )

        XCTAssertEqual(presentation.visualState, .meetingSoon)
        XCTAssertEqual(presentation.title, "30s")
    }

    /// 验证正好 1 小时无零分钟时英文显示"1h"而不是"1h 0m"。
    func testExactlyOneHourInEnglishProducesCompactHourFormat() {
        let meetingStart = fixedNow.addingTimeInterval(3600)
        let presentation = MenuBarPresentationCalculator.calculate(
            reminderState: .idle(message: "No reminder."),
            sourceCoordinatorState: readyState(nextMeetingAt: meetingStart),
            now: fixedNow,
            uiLanguage: .english
        )

        XCTAssertEqual(presentation.title, "1h")
    }

    // MARK: - Test helpers

    private func countdownContext(
        meetingStartAt: Date,
        now: Date,
        meetingTitle: String = "设计评审"
    ) -> ScheduledReminderContext {
        let meeting = MeetingRecord(
            id: "test-meeting",
            title: meetingTitle,
            startAt: meetingStartAt,
            endAt: meetingStartAt.addingTimeInterval(3_600),
            source: MeetingSourceDescriptor(
                sourceIdentifier: "test-source",
                displayName: "Test Calendar"
            )
        )

        return ScheduledReminderContext(
            meeting: meeting,
            triggerAt: now,
            countdownSeconds: max(1, Int(meetingStartAt.timeIntervalSince(now))),
            triggeredImmediately: false
        )
    }

    private func readyState(nextMeetingAt: Date) -> SourceCoordinatorState {
        let meeting = MeetingRecord(
            id: "test-meeting",
            title: "设计评审",
            startAt: nextMeetingAt,
            endAt: nextMeetingAt.addingTimeInterval(3_600),
            source: MeetingSourceDescriptor(
                sourceIdentifier: "test-source",
                displayName: "Test Calendar"
            )
        )

        return SourceCoordinatorState(
            healthState: .ready(message: "日历读取正常"),
            lastRefreshAt: nil,
            nextMeeting: meeting,
            meetings: [meeting],
            isRefreshing: false,
            lastErrorMessage: nil
        )
    }

    private func readyStateWithNoMeeting() -> SourceCoordinatorState {
        SourceCoordinatorState(
            healthState: .ready(message: "日历读取正常"),
            lastRefreshAt: nil,
            nextMeeting: nil,
            meetings: [],
            isRefreshing: false,
            lastErrorMessage: nil
        )
    }

    private func unconfiguredState() -> SourceCoordinatorState {
        SourceCoordinatorState(
            healthState: .unconfigured(message: "尚未完成接入"),
            lastRefreshAt: nil,
            nextMeeting: nil,
            meetings: [],
            isRefreshing: false,
            lastErrorMessage: nil
        )
    }

    private func failedState() -> SourceCoordinatorState {
        SourceCoordinatorState(
            healthState: .failed(message: "读取失败"),
            lastRefreshAt: nil,
            nextMeeting: nil,
            meetings: [],
            isRefreshing: false,
            lastErrorMessage: nil
        )
    }
}
