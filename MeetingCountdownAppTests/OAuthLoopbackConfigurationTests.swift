import Foundation
import XCTest
@testable import FeishuMeetingCountdown

/// 这组测试的目标不是验证网络行为，而是把项目约定的固定回调地址钉死到代码里。
final class OAuthLoopbackConfigurationTests: XCTestCase {
    /// 验证默认飞书回调地址与文档约定完全一致。
    func testFeishuDefaultCallbackURLMatchesProjectContract() {
        let configuration = OAuthLoopbackConfiguration.feishuDefault

        XCTAssertEqual(configuration.host, "127.0.0.1")
        XCTAssertEqual(configuration.port, 23388)
        XCTAssertEqual(configuration.callbackPath, "/oauth/callback")
        XCTAssertEqual(configuration.callbackURL.absoluteString, "http://127.0.0.1:23388/oauth/callback")
    }
}
