import XCTest
@testable import FeishuMeetingCountdown

/// 这些测试锁定设置场景打开桥接器最基础的登记和调用语义。
@MainActor
final class SettingsSceneOpenControllerTests: XCTestCase {
    /// 在 SwiftUI 视图还没登记 `openSettings` 动作之前，桥接器不应该伪装成自己能打开设置。
    func testOpenSettingsIfAvailableReturnsFalseWithoutRegisteredAction() {
        let controller = SettingsSceneOpenController()

        XCTAssertFalse(controller.openSettingsIfAvailable())
    }

    /// 一旦菜单弹层把官方动作登记进来，桥接器就应该按原样调用它。
    func testOpenSettingsIfAvailableInvokesRegisteredAction() {
        let controller = SettingsSceneOpenController()
        var callCount = 0

        controller.register {
            callCount += 1
        }

        XCTAssertTrue(controller.openSettingsIfAvailable())
        XCTAssertEqual(callCount, 1)
    }

    /// 如果 SwiftUI 视图重复挂载，新的动作登记应该覆盖旧动作，确保后续仍然调用最新环境值。
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
