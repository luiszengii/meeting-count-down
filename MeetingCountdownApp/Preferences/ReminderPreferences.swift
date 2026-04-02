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
    /// 默认关闭的“仅在耳机连接时播放”策略。
    /// 开启后只有在当前默认输出设备被识别为私密收听设备时才真正播放提醒音频。
    var playSoundOnlyWhenHeadphonesConnected: Bool
    /// 只对包含视频会议信息的事件建立提醒。
    /// 当前以标准化后的 `.vc` 链接类型为判断依据。
    var onlyForMeetingsWithVideoLink: Bool
    /// 是否跳过当前用户已明确拒绝的会议。
    /// 这里默认开启，避免把已拒绝的会议继续当成下一场会议。
    var skipDeclinedMeetings: Bool

    /// 显式提供带默认值的初始化器，避免调用方在只想覆盖一两个字段时重复填满整份偏好。
    init(
        countdownOverrideSeconds: Int? = nil,
        globalReminderEnabled: Bool = true,
        isMuted: Bool = false,
        playSoundOnlyWhenHeadphonesConnected: Bool = false,
        onlyForMeetingsWithVideoLink: Bool = false,
        skipDeclinedMeetings: Bool = true
    ) {
        self.countdownOverrideSeconds = countdownOverrideSeconds
        self.globalReminderEnabled = globalReminderEnabled
        self.isMuted = isMuted
        self.playSoundOnlyWhenHeadphonesConnected = playSoundOnlyWhenHeadphonesConnected
        self.onlyForMeetingsWithVideoLink = onlyForMeetingsWithVideoLink
        self.skipDeclinedMeetings = skipDeclinedMeetings
    }

    /// 首版默认值：不覆盖倒计时秒数、提醒总开关开启、默认非静音，
    /// 耳机策略默认关闭、视频会议过滤默认关闭、拒绝会议默认跳过。
    static let `default` = ReminderPreferences()
}
