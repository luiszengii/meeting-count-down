import EventKit
import XCTest
@testable import FeishuMeetingCountdown

/// 这些测试锁定 Phase 1 真实诊断检查器的映射行为。
final class DiagnosticCheckersTests: XCTestCase {
    /// 验证系统日历拿到 full access 时，会被映射成可继续的通过状态。
    func testSystemCalendarPermissionDiagnosticMapsFullAccessToPassed() async {
        let diagnostic = SystemCalendarPermissionDiagnostic {
            .fullAccess
        }

        let status = await diagnostic.run()

        XCTAssertEqual(status, .passed(message: "系统日历权限已授权，可继续 CalDAV / 系统日历路线"))
    }
}
