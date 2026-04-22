import Foundation

/// `ReminderPreferencesController` 负责把设置页里的提醒偏好交互收口成单一状态对象。
/// 视图层只负责展示当前值和发起动作，不直接自己读写 `PreferencesStore`。
///
/// 遵从 `AsyncStateController`：
/// - `loadingState` 对应原 `isLoadingState`（读取偏好时的忙碌标志）。
/// - `isSavingState` 保留为独立属性（写入偏好时的忙碌标志），与 `loadingState` 语义不同，
///   因此不合并。视图层同时检查两者来决定是否禁用交互。
/// - `errorMessage` 对应原 `lastErrorMessage`。
@MainActor
final class ReminderPreferencesController: ObservableObject, AsyncStateController {
    /// 当前已经加载到内存里的提醒偏好。
    @Published private(set) var reminderPreferences: ReminderPreferences
    /// 当前是否正在读取真实存储里的偏好。（AsyncStateController.loadingState）
    @Published var loadingState: Bool
    /// 当前是否正在把新偏好写回持久化层。
    @Published private(set) var isSavingState: Bool
    /// 最近一次用户可见错误。（AsyncStateController.errorMessage）
    @Published var errorMessage: String?

    /// 非敏感偏好持久化入口。
    private let preferencesStore: any PreferencesStore
    /// 每次成功保存提醒偏好后，都要统一通知上游重算当前下一场会议和提醒任务。
    private let onPreferencesChanged: @MainActor @Sendable () async -> Void

    init(
        preferencesStore: any PreferencesStore,
        onPreferencesChanged: @escaping @MainActor @Sendable () async -> Void = {},
        autoRefreshOnStart: Bool = true
    ) {
        self.preferencesStore = preferencesStore
        self.onPreferencesChanged = onPreferencesChanged
        self.reminderPreferences = .default
        self.loadingState = false
        self.isSavingState = false
        self.errorMessage = nil

        if autoRefreshOnStart {
            Task { [weak self] in
                await self?.refresh()
            }
        }
    }

    /// 从真实存储重新加载提醒偏好（`AsyncStateController.performRefresh` 的实现）。
    func performRefresh() async throws {
        reminderPreferences = await preferencesStore.loadReminderPreferences()
    }

    /// 切换总提醒开关。
    func setGlobalReminderEnabled(_ isEnabled: Bool) async {
        await updatePreferences { $0.globalReminderEnabled = isEnabled }
    }

    /// 切换静音模式。
    func setMuted(_ isMuted: Bool) async {
        await updatePreferences { $0.isMuted = isMuted }
    }

    /// 切换"仅耳机输出时播放"。
    func setPlaySoundOnlyWhenHeadphonesConnected(_ isEnabled: Bool) async {
        await updatePreferences { $0.playSoundOnlyWhenHeadphonesConnected = isEnabled }
    }

    /// 切换"仅提醒含视频会议信息的事件"。
    func setOnlyForMeetingsWithVideoLink(_ isEnabled: Bool) async {
        await updatePreferences { $0.onlyForMeetingsWithVideoLink = isEnabled }
    }

    /// 切换"跳过已拒绝会议"。
    func setSkipDeclinedMeetings(_ isEnabled: Bool) async {
        await updatePreferences { $0.skipDeclinedMeetings = isEnabled }
    }

    /// 设置倒计时覆盖秒数；传 `nil` 表示恢复为"跟随默认音效时长"。
    func setCountdownOverrideSeconds(_ seconds: Int?) async {
        await updatePreferences { preferences in
            if let seconds {
                preferences.countdownOverrideSeconds = max(1, seconds)
            } else {
                preferences.countdownOverrideSeconds = nil
            }
        }
    }

    /// 切换当前壳层界面语言。
    /// 语言变化只影响视图层展示，不需要触发会议重读或提醒重算。
    func setInterfaceLanguage(_ language: AppUILanguage) async {
        await updatePreferences(notifyUpstream: false) { $0.interfaceLanguage = language }
    }

    /// 统一保存提醒偏好并在成功后通知上游重算。
    private func updatePreferences(
        notifyUpstream: Bool = true,
        _ mutate: (inout ReminderPreferences) -> Void
    ) async {
        var updatedPreferences = reminderPreferences
        mutate(&updatedPreferences)

        guard updatedPreferences != reminderPreferences else {
            return
        }

        reminderPreferences = updatedPreferences
        isSavingState = true
        errorMessage = nil

        defer {
            isSavingState = false
        }

        do {
            try await preferencesStore.saveReminderPreferences(updatedPreferences)
            if notifyUpstream {
                await onPreferencesChanged()
            }
        } catch {
            errorMessage = error.localizedDescription
            reminderPreferences = await preferencesStore.loadReminderPreferences()
        }
    }
}
