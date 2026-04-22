import Foundation
@testable import FeishuMeetingCountdown

/// 固定时钟实现，用于让测试完全控制"当前时间"，避免断言依赖真实时钟。
/// 此文件被所有需要固定当前时间的测试文件共享。
struct FixedDateProvider: DateProviding {
    /// 测试注入的固定当前时间。
    let currentDate: Date

    /// 直接返回注入的固定时间。
    func now() -> Date {
        currentDate
    }
}
