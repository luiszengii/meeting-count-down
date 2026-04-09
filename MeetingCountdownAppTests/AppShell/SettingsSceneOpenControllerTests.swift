import XCTest
@testable import FeishuMeetingCountdown

/// 这些测试锁定设置窗口打开桥接器最基础的登记和调用语义。
@MainActor
final class SettingsSceneOpenControllerTests: XCTestCase {
    /// 在壳层还没登记打开动作之前，桥接器不应该伪装成自己能打开设置。
    func testOpenSettingsIfAvailableReturnsFalseWithoutRegisteredAction() {
        let controller = SettingsSceneOpenController()

        XCTAssertFalse(controller.openSettingsIfAvailable())
    }

    /// 一旦壳层把打开动作登记进来，桥接器就应该按原样调用它。
    func testOpenSettingsIfAvailableInvokesRegisteredAction() {
        let controller = SettingsSceneOpenController()
        var callCount = 0

        controller.register {
            callCount += 1
        }

        XCTAssertTrue(controller.openSettingsIfAvailable())
        XCTAssertEqual(callCount, 1)
    }

    /// 如果后续切换了打开实现，新的动作登记应该覆盖旧动作，确保入口总是命中最新链路。
    func testRegisterReplacesPreviouslyRegisteredAction() {
        let controller = SettingsSceneOpenController()
        var firstActionCallCount = 0
        var secondActionCallCount = 0

        controller.register {
            firstActionCallCount += 1
        }
        controller.register {
            secondActionCallCount += 1
        }

        XCTAssertTrue(controller.openSettingsIfAvailable())
        XCTAssertEqual(firstActionCallCount, 0)
        XCTAssertEqual(secondActionCallCount, 1)
    }
}
