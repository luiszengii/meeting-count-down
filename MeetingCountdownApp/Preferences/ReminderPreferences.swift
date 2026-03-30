import Foundation

/// `ReminderPreferences` 预留首版提醒相关偏好。
/// Phase 0 先把默认值和字段语义固定下来，后续设置窗口和真实存储实现可以直接围绕它展开。
struct ReminderPreferences: Equatable, Sendable {
    /// 如果用户手动指定倒计时秒数，就覆盖音效文件时长。
    var countdownOverrideSeconds: Int?
    /// 总提醒开关，关掉后不再触发任何提醒动作。
    var globalReminderEnabled: Bool
    /// 静音开关，保留倒计时逻辑但不播放声音。
    var isMuted: Bool

    /// 首版默认值：不覆盖倒计时秒数、提醒总开关开启、默认非静音。
    static let `default` = ReminderPreferences(
        countdownOverrideSeconds: nil,
        globalReminderEnabled: true,
        isMuted: false
    )
}
