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

    /// 验证从未成功刷新过系统日历时，会进入 warning 而不是伪装成通过。
    func testSyncFreshnessDiagnosticWarnsWhenNoSuccessfulRefreshExists() async {
        let diagnostic = SyncFreshnessDiagnostic(lastSuccessfulRefreshAt: nil) {
            Date(timeIntervalSince1970: 600)
        }

        let status = await diagnostic.run()

        XCTAssertEqual(status, .warning(message: "尚未成功读取本地系统日历"))
    }

    /// 验证超过 10 分钟未成功刷新时，会进入 warning。
    func testSyncFreshnessDiagnosticWarnsWhenRefreshIsStale() {
        let status = SyncFreshnessDiagnostic.status(
            lastSuccessfulRefreshAt: Date(timeIntervalSince1970: 0),
            now: Date(timeIntervalSince1970: 11 * 60)
        )

        XCTAssertEqual(status, .warning(message: "距离最近一次成功读取本地系统日历已过去 11 分钟"))
    }
}
