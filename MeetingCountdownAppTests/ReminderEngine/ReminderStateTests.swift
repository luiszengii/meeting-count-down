import Foundation
import XCTest
@testable import FeishuMeetingCountdown

/// 这些测试锁定菜单栏提醒展示的秒级倒计时、闪烁节奏和“会议开始”文案规则。
@MainActor
final class ReminderStateTests: XCTestCase {
    /// 验证正常播放型提醒在会前阶段会显示剩余秒数，而不是固定短文案。
    func testPlayingPresentationShowsRemainingCountdownSecondsBeforeMeetingStarts() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let state = ReminderState.playing(
            context: countdownContext(now: now, offsetSeconds: 20),
            startedAt: now
        )

        XCTAssertEqual(
            state.menuBarAlertPresentation(at: now),
            ReminderMenuBarAlertPresentation(
                title: "20s",
                symbolName: "timer.circle.fill",
                isHighPriority: true,
                showsCapsuleBackground: true,
                shouldHighlightRed: false
            )
        )
    }

    /// 验证最后 `10 ... 5` 秒按“一秒一闪”的节奏进入红色强调态。
    func testPlayingPresentationFlashesRedOncePerSecondDuringFinalSevenSeconds() {
        let flashOnNow = Date(timeIntervalSinceReferenceDate: 100.1)
        let flashOffNow = Date(timeIntervalSinceReferenceDate: 100.6)
        let state = ReminderState.playing(
            context: countdownContext(now: flashOnNow, offsetSeconds: 5),
            startedAt: flashOnNow
        )

        XCTAssertEqual(
            state.menuBarAlertPresentation(at: flashOnNow)?.shouldHighlightRed,
            true
        )
        XCTAssertEqual(
            state.menuBarAlertPresentation(at: flashOffNow)?.shouldHighlightRed,
            false
        )
    }

    /// 验证最后 `4 ... 1` 秒切换为“一秒两闪”，闪烁节奏比前一阶段更密。
    func testPlayingPresentationFlashesRedTwicePerSecondDuringFinalFourSeconds() {
        let flashOnNow = Date(timeIntervalSinceReferenceDate: 100.1)
        let flashOffNow = Date(timeIntervalSinceReferenceDate: 100.3)
        let state = ReminderState.playing(
            context: countdownContext(now: flashOnNow, offsetSeconds: 4),
            startedAt: flashOnNow
        )

        XCTAssertEqual(
            state.menuBarAlertPresentation(at: flashOnNow)?.shouldHighlightRed,
            true
        )
        XCTAssertEqual(
            state.menuBarAlertPresentation(at: flashOffNow)?.shouldHighlightRed,
            false
        )
    }

    /// 验证会议真正开始后，菜单栏只保留会议标题，不再额外拼接“会议开始”后缀。
    func testPlayingPresentationShowsMeetingTitleOnlyAfterMeetingStarts() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let context = countdownContext(now: now, offsetSeconds: 3, meetingTitle: "团队周会")
        let state = ReminderState.playing(context: context, startedAt: now)
        let meetingStartAt = context.meeting.startAt

        XCTAssertEqual(
            state.menuBarAlertPresentation(at: meetingStartAt),
            ReminderMenuBarAlertPresentation(
                title: "团队周会",
                symbolName: "exclamationmark.circle.fill",
                isHighPriority: true,
                showsCapsuleBackground: true,
                shouldHighlightRed: false
            )
        )
    }

    /// 验证静默命中仍保留原因型文案，不会被会议标题完成态覆盖。
    func testTriggeredSilentlyPresentationKeepsReasonSpecificCopy() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let context = countdownContext(now: now, offsetSeconds: 1)
        let state = ReminderState.triggeredSilently(
            context: context,
            triggeredAt: now,
            reason: .outputRoutePolicy(routeName: "MacBook Pro Speakers")
        )

        XCTAssertEqual(
            state.menuBarAlertPresentation(at: context.meeting.startAt)?.title,
            "避免外放"
        )
    }

    /// 用统一入口构造菜单栏倒计时上下文，避免每个测试都重复拼接样板会议。
    private func countdownContext(
        now: Date,
        offsetSeconds: Int,
        meetingTitle: String = "设计评审"
    ) -> ScheduledReminderContext {
        let meeting = MeetingRecord(
            id: "meeting-\(offsetSeconds)",
            title: meetingTitle,
            startAt: now.addingTimeInterval(TimeInterval(offsetSeconds)),
            endAt: now.addingTimeInterval(TimeInterval(offsetSeconds + 1_800)),
            source: MeetingSourceDescriptor(
                sourceIdentifier: "test-system-calendar",
                displayName: "CalDAV / 系统日历"
            )
        )

        return ScheduledReminderContext(
            meeting: meeting,
            triggerAt: now,
            countdownSeconds: max(1, offsetSeconds),
            triggeredImmediately: true
        )
    }
}
