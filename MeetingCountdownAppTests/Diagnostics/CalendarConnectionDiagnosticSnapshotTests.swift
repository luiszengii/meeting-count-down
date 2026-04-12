import Foundation
import XCTest
@testable import FeishuMeetingCountdown

/// 这些测试锁定“接入诊断快照”导出的关键信息，避免后续为了改 UI 文案把真正有用的排查字段删掉。
final class CalendarConnectionDiagnosticSnapshotTests: XCTestCase {
    /// 验证当持久化里还留着旧日历 ID、但当前系统列表里已经没有它们时，诊断快照会明确标出这个失配状态。
    func testDiagnosticSnapshotHighlightsUnavailableStoredSelection() {
        let snapshot = CalendarConnectionDiagnosticSnapshot(
            generatedAt: fixedNow(),
            bundleIdentifier: "com.luiszeng.meetingcountdown",
            appVersion: "0.1.0",
            buildNumber: "1",
            authorizationState: .authorized,
            healthState: .unconfigured(message: "已选系统日历当前不可用，请重新选择"),
            lastSourceErrorMessage: "已选系统日历当前不可用，请重新选择",
            lastSourceRefreshAt: fixedNow(),
            lastCalendarStateLoadAt: fixedNow(),
            hasStoredCalendarSelection: true,
            storedSelectedCalendarIDs: ["missing-calendar"],
            unavailableStoredCalendarIDs: ["missing-calendar"],
            effectiveSelectedCalendarIDs: [],
            availableCalendars: [
                SystemCalendarDescriptor(
                    id: "feishu",
                    title: "飞书日历",
                    sourceTitle: "caldav.feishu.cn",
                    sourceTypeLabel: "CalDAV",
                    isSuggestedByDefault: true
                )
            ]
        )

        XCTAssertEqual(snapshot.selectionDebugState, "stored_selection_missing_from_current_calendar_list")
        XCTAssertTrue(snapshot.reportText.contains("stored_selected_calendar_ids: missing-calendar"))
        XCTAssertTrue(snapshot.reportText.contains("unavailable_stored_calendar_ids: missing-calendar"))
        XCTAssertTrue(snapshot.reportText.contains("selection_debug_state: stored_selection_missing_from_current_calendar_list"))
        XCTAssertTrue(snapshot.reportText.contains("- 飞书日历 | source=caldav.feishu.cn | type=CalDAV | id=feishu | flags=suggested"))
    }

    /// 统一返回固定时间，避免 UTC 文本格式断言依赖真实当前时钟。
    private func fixedNow() -> Date {
        Date(timeIntervalSince1970: 1_744_563_200)
    }
}
