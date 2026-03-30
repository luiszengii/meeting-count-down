import Foundation
import OSLog

/// `AppLogger` 把系统日志封装成极小的可复用接口。
/// 现在主要目的是让 `SourceCoordinator` 和未来接入模块都能统一输出结构化日志，
/// 同时避免在业务代码里到处重复写 subsystem/category 初始化。
struct AppLogger: Sendable {
    /// 底层真正写入系统日志的 `Logger` 实例。
    private let logger: Logger

    /// 通过统一 subsystem 和可变 category 生成结构化日志器。
    init(source: String) {
        logger = Logger(subsystem: "com.luiszeng.meetingcountdown", category: source)
    }

    /// 记录普通信息级日志。
    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    /// 记录错误级日志。
    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
