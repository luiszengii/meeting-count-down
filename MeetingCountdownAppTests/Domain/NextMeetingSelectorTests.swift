import Foundation
import XCTest
@testable import FeishuMeetingCountdown

/// 这些测试锁定“下一场会议”的基础规则，避免未来接入真实源时把选择逻辑分散到各处。
final class NextMeetingSelectorTests: XCTestCase {
    /// 被测对象，直接使用默认规则实现。
    private let selector = DefaultNextMeetingSelector()
    /// 测试里统一复用同一份来源描述，避免每个用例重复构造。
    private let calendarSource = MeetingSourceDescriptor(
        sourceIdentifier: "test-source",
        displayName: "测试系统日历"
    )

    /// 验证空列表时不会凭空构造会议结果。
    func testEmptyListReturnsNil() {
        let now = makeDate(hour: 9, minute: 0)

        XCTAssertNil(selector.selectNextMeeting(from: [], now: now))
    }

    /// 验证选择器会跳过不应提醒的全天事件和已取消事件。
    func testSelectorSkipsAllDayAndCancelledMeetings() {
        let now = makeDate(hour: 9, minute: 0)
        let meetings = [
            makeMeeting(id: "all-day", title: "全天事件", startHour: 10, minute: 0, isAllDay: true),
            makeMeeting(id: "cancelled", title: "取消事件", startHour: 10, minute: 5, isCancelled: true),
            makeMeeting(id: "usable", title: "有效会议", startHour: 10, minute: 10)
        ]

        let nextMeeting = selector.selectNextMeeting(from: meetings, now: now)

        XCTAssertEqual(nextMeeting?.id, "usable")
    }

    /// 验证真正返回的是“离现在最近的未来会议”，而不是输入顺序里的第一项。
    func testSelectorReturnsClosestFutureMeeting() {
        let now = makeDate(hour: 9, minute: 0)
        let meetings = [
            makeMeeting(id: "later", title: "更晚会议", startHour: 11, minute: 0),
            makeMeeting(id: "earliest", title: "最早会议", startHour: 9, minute: 30),
            makeMeeting(id: "started", title: "已开始会议", startHour: 8, minute: 55)
        ]

        let nextMeeting = selector.selectNextMeeting(from: meetings, now: now)

        XCTAssertEqual(nextMeeting?.id, "earliest")
    }

    /// 构造测试会议。
    /// 这里把默认时长统一设成 30 分钟，让测试只关注选择规则，不被无关时长细节干扰。
    private func makeMeeting(
        id: String,
        title: String,
        startHour: Int,
        minute: Int,
        isAllDay: Bool = false,
        isCancelled: Bool = false
    ) -> MeetingRecord {
        let startAt = makeDate(hour: startHour, minute: minute)
        let endAt = Calendar(identifier: .gregorian).date(byAdding: .minute, value: 30, to: startAt)!

        return MeetingRecord(
            id: id,
            title: title,
            startAt: startAt,
            endAt: endAt,
            isAllDay: isAllDay,
            isCancelled: isCancelled,
            source: calendarSource
        )
    }

    /// 统一生成固定日期上的时间点，保证测试不依赖真实当前时间。
    private func makeDate(hour: Int, minute: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: hour, minute: minute))!
    }
}
