import Foundation

/// `PreferencesStore` 把“偏好模型是什么”和“偏好具体存在哪里”解耦。
/// 这样 Phase 0 可以先用内存实现把接口定住，Phase 2 再把连接模式和系统日历选择接进真实持久化。
protocol PreferencesStore: Sendable {
    /// 读取当前提醒偏好。
    /// 使用异步接口是为了让未来切换到 `UserDefaults`、文件系统甚至迁移流程时不必改调用方签名。
    func loadReminderPreferences() async -> ReminderPreferences
    /// 写入新的提醒偏好。
    func saveReminderPreferences(_ reminderPreferences: ReminderPreferences) async throws
    /// 读取用户选中的系统日历 ID 集合。
    /// 这个集合只对 CalDAV / 系统日历桥接生效。
    func loadSelectedSystemCalendarIDs() async -> Set<String>
    /// 保存用户选中的系统日历 ID 集合。
    func saveSelectedSystemCalendarIDs(_ identifiers: Set<String>) async throws
    /// 返回系统日历选择是否已经被用户显式保存过。
    /// 这样控制器才能区分“从未选择过”和“用户主动清空了选择”。
    func hasStoredSelectedSystemCalendarIDs() async -> Bool
    /// 读取最近一次成功读取系统日历的时间。
    /// 这个值会同时服务于同步新鲜度提示和设置页状态展示。
    func loadLastSuccessfulRefreshAt() async -> Date?
    /// 保存最近一次成功读取系统日历的时间。
    func saveLastSuccessfulRefreshAt(_ date: Date?) async throws
    /// 读取当前已经导入的提醒音频列表。
    func loadSoundProfiles() async -> [SoundProfile]
    /// 保存当前已经导入的提醒音频列表。
    func saveSoundProfiles(_ soundProfiles: [SoundProfile]) async throws
    /// 读取当前正式提醒使用的音频 ID。
    func loadSelectedSoundProfileID() async -> String?
    /// 保存当前正式提醒使用的音频 ID。
    func saveSelectedSoundProfileID(_ soundProfileID: String?) async throws
}

actor InMemoryPreferencesStore: PreferencesStore {
    /// actor 内部持有当前偏好值，利用 actor 隔离避免并发读写竞争。
    private var reminderPreferences: ReminderPreferences
    /// 当前选中的系统日历 ID 集合。
    private var selectedSystemCalendarIDs: Set<String>
    /// 标记系统日历选择是否已经被用户显式保存过。
    private var hasStoredSystemCalendarSelection: Bool
    /// 最近一次成功刷新系统日历的时间。
    private var lastSuccessfulRefreshAt: Date?
    /// 当前已经导入的提醒音频列表。
    private var soundProfiles: [SoundProfile]
    /// 当前正式提醒使用的音频 ID。
    private var selectedSoundProfileID: String?

    /// 允许测试或应用装配时注入自定义默认值。
    init(
        reminderPreferences: ReminderPreferences = .default,
        selectedSystemCalendarIDs: Set<String> = [],
        hasStoredSelectedSystemCalendarIDs: Bool = false,
        lastSuccessfulRefreshAt: Date? = nil,
        soundProfiles: [SoundProfile] = [],
        selectedSoundProfileID: String? = nil
    ) {
        self.reminderPreferences = reminderPreferences
        self.selectedSystemCalendarIDs = selectedSystemCalendarIDs
        self.hasStoredSystemCalendarSelection = hasStoredSelectedSystemCalendarIDs || !selectedSystemCalendarIDs.isEmpty
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.soundProfiles = soundProfiles
        self.selectedSoundProfileID = selectedSoundProfileID
    }

    /// 直接返回 actor 内部持有的当前偏好值。
    func loadReminderPreferences() async -> ReminderPreferences {
        reminderPreferences
    }

    /// Phase 0 先简单覆盖内存值，后续再接入真实持久化和错误处理。
    func saveReminderPreferences(_ reminderPreferences: ReminderPreferences) async throws {
        self.reminderPreferences = reminderPreferences
    }

    /// 返回当前已选系统日历 ID。
    func loadSelectedSystemCalendarIDs() async -> Set<String> {
        selectedSystemCalendarIDs
    }

    /// 覆盖当前已选系统日历 ID。
    func saveSelectedSystemCalendarIDs(_ identifiers: Set<String>) async throws {
        selectedSystemCalendarIDs = identifiers
        hasStoredSystemCalendarSelection = true
    }

    /// 返回当前这份选择是否已经被保存过。
    func hasStoredSelectedSystemCalendarIDs() async -> Bool {
        hasStoredSystemCalendarSelection
    }

    /// 返回测试里记录的最近成功刷新时间。
    func loadLastSuccessfulRefreshAt() async -> Date? {
        lastSuccessfulRefreshAt
    }

    /// 覆盖最近成功刷新时间。
    func saveLastSuccessfulRefreshAt(_ date: Date?) async throws {
        lastSuccessfulRefreshAt = date
    }

    /// 读取测试里记录的已导入提醒音频列表。
    func loadSoundProfiles() async -> [SoundProfile] {
        soundProfiles
    }

    /// 覆盖已导入提醒音频列表。
    func saveSoundProfiles(_ soundProfiles: [SoundProfile]) async throws {
        self.soundProfiles = soundProfiles
    }

    /// 读取当前选中的提醒音频 ID。
    func loadSelectedSoundProfileID() async -> String? {
        selectedSoundProfileID
    }

    /// 覆盖当前选中的提醒音频 ID。
    func saveSelectedSoundProfileID(_ soundProfileID: String?) async throws {
        selectedSoundProfileID = soundProfileID
    }
}

/// `UserDefaultsPreferencesStore` 是当前应用的真实非敏感偏好持久化实现。
/// 当前主要落地提醒偏好与 CalDAV 相关的系统日历选择；不再保存多接入模式。
actor UserDefaultsPreferencesStore: PreferencesStore {
    /// 统一管理所有非敏感偏好的读写入口。
    private let userDefaults: UserDefaults

    /// 允许测试传入隔离的 suite，也允许生产环境默认使用标准容器。
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// 允许测试只传 `suiteName`，避免把同一个 `UserDefaults` 实例跨 actor 共享。
    init(suiteName: String) {
        self.userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// 读取提醒偏好；当前字段不多，直接逐项从 `UserDefaults` 解码即可。
    func loadReminderPreferences() async -> ReminderPreferences {
        ReminderPreferences(
            countdownOverrideSeconds: userDefaults.object(forKey: Keys.countdownOverrideSeconds) as? Int,
            globalReminderEnabled: userDefaults.object(forKey: Keys.globalReminderEnabled) as? Bool ?? true,
            isMuted: userDefaults.object(forKey: Keys.isMuted) as? Bool ?? false,
            playSoundOnlyWhenHeadphonesConnected: userDefaults.object(forKey: Keys.playSoundOnlyWhenHeadphonesConnected) as? Bool ?? false,
            onlyForMeetingsWithVideoLink: userDefaults.object(forKey: Keys.onlyForMeetingsWithVideoLink) as? Bool ?? false,
            skipDeclinedMeetings: userDefaults.object(forKey: Keys.skipDeclinedMeetings) as? Bool ?? true
        )
    }

    /// 把提醒偏好逐项写入 `UserDefaults`。
    func saveReminderPreferences(_ reminderPreferences: ReminderPreferences) async throws {
        userDefaults.set(reminderPreferences.countdownOverrideSeconds, forKey: Keys.countdownOverrideSeconds)
        userDefaults.set(reminderPreferences.globalReminderEnabled, forKey: Keys.globalReminderEnabled)
        userDefaults.set(reminderPreferences.isMuted, forKey: Keys.isMuted)
        userDefaults.set(
            reminderPreferences.playSoundOnlyWhenHeadphonesConnected,
            forKey: Keys.playSoundOnlyWhenHeadphonesConnected
        )
        userDefaults.set(
            reminderPreferences.onlyForMeetingsWithVideoLink,
            forKey: Keys.onlyForMeetingsWithVideoLink
        )
        userDefaults.set(
            reminderPreferences.skipDeclinedMeetings,
            forKey: Keys.skipDeclinedMeetings
        )
    }

    /// 读取已选系统日历 ID，并统一转成集合避免重复。
    func loadSelectedSystemCalendarIDs() async -> Set<String> {
        Self.bootstrapSelectedSystemCalendarIDs(userDefaults: userDefaults)
    }

    /// 把当前系统日历选择写成稳定排序后的数组，便于调试和比较。
    func saveSelectedSystemCalendarIDs(_ identifiers: Set<String>) async throws {
        userDefaults.set(Array(identifiers).sorted(), forKey: Keys.selectedSystemCalendarIDs)
    }

    /// 只要对应 key 存在，无论数组是不是空，都说明用户已经显式保存过一次选择。
    func hasStoredSelectedSystemCalendarIDs() async -> Bool {
        userDefaults.object(forKey: Keys.selectedSystemCalendarIDs) != nil
    }

    /// 读取最近一次成功刷新时间；当前直接按 `Date` 原生对象往返。
    func loadLastSuccessfulRefreshAt() async -> Date? {
        userDefaults.object(forKey: Keys.lastSuccessfulRefreshAt) as? Date
    }

    /// 保存最近一次成功刷新时间；传 `nil` 时显式清掉旧值。
    func saveLastSuccessfulRefreshAt(_ date: Date?) async throws {
        if let date {
            userDefaults.set(date, forKey: Keys.lastSuccessfulRefreshAt)
        } else {
            userDefaults.removeObject(forKey: Keys.lastSuccessfulRefreshAt)
        }
    }

    /// 读取已导入提醒音频列表；解码失败时回退为空列表，避免旧脏数据把设置页彻底卡住。
    func loadSoundProfiles() async -> [SoundProfile] {
        guard let data = userDefaults.data(forKey: Keys.soundProfiles) else {
            return []
        }

        do {
            return try JSONDecoder().decode([SoundProfile].self, from: data)
        } catch {
            return []
        }
    }

    /// 把当前提醒音频列表编码后写回 `UserDefaults`。
    func saveSoundProfiles(_ soundProfiles: [SoundProfile]) async throws {
        let data = try JSONEncoder().encode(soundProfiles)
        userDefaults.set(data, forKey: Keys.soundProfiles)
    }

    /// 读取当前正式提醒使用的音频 ID。
    func loadSelectedSoundProfileID() async -> String? {
        userDefaults.string(forKey: Keys.selectedSoundProfileID)
    }

    /// 保存当前正式提醒使用的音频 ID；传 `nil` 时清除旧选择。
    func saveSelectedSoundProfileID(_ soundProfileID: String?) async throws {
        if let soundProfileID {
            userDefaults.set(soundProfileID, forKey: Keys.selectedSoundProfileID)
        } else {
            userDefaults.removeObject(forKey: Keys.selectedSoundProfileID)
        }
    }

    /// 同步读取当前已选日历 ID，供 app 启动装配和桥接层初始化复用。
    nonisolated static func bootstrapSelectedSystemCalendarIDs(userDefaults: UserDefaults = .standard) -> Set<String> {
        let identifiers = userDefaults.array(forKey: Keys.selectedSystemCalendarIDs) as? [String] ?? []
        return Set(identifiers)
    }

    /// 同步读取最近一次成功刷新时间，供 app 启动阶段在首次真正刷新完成前展示旧状态。
    nonisolated static func bootstrapLastSuccessfulRefreshAt(userDefaults: UserDefaults = .standard) -> Date? {
        userDefaults.object(forKey: Keys.lastSuccessfulRefreshAt) as? Date
    }

    /// 统一管理所有 `UserDefaults` 键名，避免散落字符串常量。
    private enum Keys {
        static let countdownOverrideSeconds = "reminder_preferences.countdown_override_seconds"
        static let globalReminderEnabled = "reminder_preferences.global_reminder_enabled"
        static let isMuted = "reminder_preferences.is_muted"
        static let playSoundOnlyWhenHeadphonesConnected =
            "reminder_preferences.play_sound_only_when_headphones_connected"
        static let onlyForMeetingsWithVideoLink =
            "reminder_preferences.only_for_meetings_with_video_link"
        static let skipDeclinedMeetings = "reminder_preferences.skip_declined_meetings"
        static let selectedSystemCalendarIDs = "connection_preferences.selected_system_calendar_ids"
        static let lastSuccessfulRefreshAt = "connection_preferences.last_successful_refresh_at"
        static let soundProfiles = "sound_profiles.imported_profiles"
        static let selectedSoundProfileID = "sound_profiles.selected_profile_id"
    }
}
