import Foundation

/// `PreferencesStore` 把“偏好模型是什么”和“偏好具体存在哪里”解耦。
/// 这样 Phase 0 可以先用内存实现把接口定住，后续再接 UserDefaults、文件系统或迁移逻辑。
protocol PreferencesStore: Sendable {
    /// 读取当前提醒偏好。
    /// 使用异步接口是为了让未来切换到 `UserDefaults`、文件系统甚至迁移流程时不必改调用方签名。
    func loadReminderPreferences() async -> ReminderPreferences
    /// 写入新的提醒偏好。
    func saveReminderPreferences(_ reminderPreferences: ReminderPreferences) async throws
}

actor InMemoryPreferencesStore: PreferencesStore {
    /// actor 内部持有当前偏好值，利用 actor 隔离避免并发读写竞争。
    private var reminderPreferences: ReminderPreferences

    /// 允许测试或应用装配时注入自定义默认值。
    init(reminderPreferences: ReminderPreferences = .default) {
        self.reminderPreferences = reminderPreferences
    }

    /// 直接返回 actor 内部持有的当前偏好值。
    func loadReminderPreferences() async -> ReminderPreferences {
        reminderPreferences
    }

    /// Phase 0 先简单覆盖内存值，后续再接入真实持久化和错误处理。
    func saveReminderPreferences(_ reminderPreferences: ReminderPreferences) async throws {
        self.reminderPreferences = reminderPreferences
    }
}
