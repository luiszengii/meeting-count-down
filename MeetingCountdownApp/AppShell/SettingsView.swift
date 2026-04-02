import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// `SettingsView` 现在只承载 CalDAV 单一路径需要的配置和状态总览。
/// 它不直接操作 EventKit 原始对象，而是通过 `SystemCalendarConnectionController`、
/// `SourceCoordinator` 和 `ReminderEngine` 暴露出来的聚合状态驱动界面。
struct SettingsView: View {
    /// 设置窗口和菜单栏共享同一份数据源协调层。
    @ObservedObject var sourceCoordinator: SourceCoordinator
    /// CalDAV / 系统日历路线的真实配置状态和动作入口。
    @ObservedObject var systemCalendarConnectionController: SystemCalendarConnectionController
    /// 设置页同样要观察提醒状态，向用户解释提醒是否已经真正建立。
    @ObservedObject var reminderEngine: ReminderEngine
    /// 提醒偏好由单独控制器管理，避免视图自己直接读写持久化层。
    @ObservedObject var reminderPreferencesController: ReminderPreferencesController
    /// 提醒音频库由独立控制器管理，负责多次导入、切换和试听。
    @ObservedObject var soundProfileLibraryController: SoundProfileLibraryController
    /// 开机启动开关需要单独管理系统注册状态和错误。
    @ObservedObject var launchAtLoginController: LaunchAtLoginController
    /// 设置页自己把真实窗口登记到这里，供菜单栏入口复用。
    let settingsWindowController: SettingsWindowController
    /// 控制 macOS 文件选择器是否弹出。
    @State private var isPresentingSoundImporter = false

    /// 统一渲染设置窗口内容。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                caldavGuideGroup
                systemCalendarConfigurationGroup
                reminderPreferencesGroup
                syncAndIntegrationGroup
                appStatusGroup
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .background(
            SettingsWindowAccessor { window in
                settingsWindowController.register(window: window)
            }
        )
        .fileImporter(
            isPresented: $isPresentingSoundImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                Task {
                    await soundProfileLibraryController.importSoundFiles(from: urls)
                }
            case let .failure(error):
                soundProfileLibraryController.reportFileImportFailure(error)
            }
        }
    }

    /// 用最短路径向用户解释当前产品只支持哪一条接入流程。
    @ViewBuilder
    private var caldavGuideGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("唯一接入路径")
                    .font(.headline)

                Text("当前版本只支持 `CalDAV -> macOS Calendar -> 本地 app`。请先在飞书日历里生成 CalDAV 配置，再到 macOS“日历”应用添加“其他 CalDAV 账户 -> 手动”，最后回到这里授权并选择目标日历。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("如果这里还没有看到飞书日历，通常说明系统日历尚未同步完成，或者 macOS Calendar 里的账户还没添加成功。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 当前设置页的核心区域：权限状态、候选日历以及日历选择。
    @ViewBuilder
    private var systemCalendarConfigurationGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("CalDAV / 系统日历配置")
                        .font(.headline)

                    Spacer()

                    Button {
                        Task {
                            await systemCalendarConnectionController.refreshState()
                            await sourceCoordinator.refresh(trigger: .manualRefresh)
                        }
                    } label: {
                        Label("重新检查", systemImage: "arrow.clockwise")
                    }
                    .disabled(systemCalendarConnectionController.isLoadingState || systemCalendarConnectionController.isRequestingAccess)

                    badge(
                        text: systemCalendarConnectionController.authorizationState.badgeText,
                        color: authorizationBadgeColor(for: systemCalendarConnectionController.authorizationState)
                    )
                }

                Text(systemCalendarConnectionController.authorizationState.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let lastLoadedAt = systemCalendarConnectionController.lastLoadedAt {
                    LabeledContent("最近检查", value: Self.absoluteFormatter.string(from: lastLoadedAt))
                }

                if let lastErrorMessage = systemCalendarConnectionController.lastErrorMessage {
                    Text(lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                switch systemCalendarConnectionController.authorizationState {
                case .authorized:
                    LabeledContent("选择状态", value: systemCalendarConnectionController.selectionSummary)

                    if systemCalendarConnectionController.isLoadingState {
                        ProgressView("正在读取系统日历…")
                            .controlSize(.small)
                    } else if systemCalendarConnectionController.availableCalendars.isEmpty {
                        Text("当前没有可读取的系统日历。请先在 macOS Calendar 中添加飞书 CalDAV 账户，再回到这里重新检查。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(systemCalendarConnectionController.availableCalendars) { calendar in
                                calendarRow(for: calendar)
                            }
                        }
                    }

                case .notDetermined:
                    Button {
                        Task {
                            await systemCalendarConnectionController.requestCalendarAccess()
                        }
                    } label: {
                        Label("授权访问日历", systemImage: "calendar.badge.plus")
                    }
                    .disabled(systemCalendarConnectionController.isRequestingAccess)

                    Text("只有在你显式点击按钮后，应用才会触发系统日历权限框。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .denied, .restricted, .writeOnly, .unknown:
                    Button {
                        openCalendarPrivacySettings()
                    } label: {
                        Label("打开系统设置", systemImage: "gearshape")
                    }

                    Text("修复权限后，可以回到这里重新检查并选择要纳入提醒的系统日历。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 当前应用运行态摘要，帮助用户区分“权限问题”“日历选择问题”“当前没有会议”和“提醒是否已建好”。
    @ViewBuilder
    private var appStatusGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("当前应用状态")
                        .font(.headline)

                    Spacer()

                    Button {
                        Task {
                            await sourceCoordinator.refresh(trigger: .manualRefresh)
                        }
                    } label: {
                        Label("立即刷新会议", systemImage: "arrow.clockwise")
                    }
                    .disabled(sourceCoordinator.state.isRefreshing)
                }

                LabeledContent("活动数据源", value: "CalDAV / 系统日历")
                LabeledContent("健康状态", value: sourceCoordinator.state.healthState.summary)
                LabeledContent("提醒状态", value: reminderEngine.state.summary)

                Text(reminderEngine.state.detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let nextMeeting = sourceCoordinator.state.nextMeeting {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("下一场会议")
                            .font(.caption.weight(.medium))
                        Text(nextMeeting.title)
                            .font(.body.weight(.medium))
                        Text(sourceCoordinator.meetingStartLine(for: nextMeeting))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("当前还没有可用于提醒的下一场会议。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let lastErrorMessage = sourceCoordinator.state.lastErrorMessage {
                    Text(lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 提醒偏好集中放在单独分组里，避免和只读状态混在一起。
    @ViewBuilder
    private var reminderPreferencesGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("提醒偏好")
                        .font(.headline)

                    Spacer()

                    if reminderPreferencesController.isLoadingState || reminderPreferencesController.isSavingState {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Toggle(
                    "启用本地提醒",
                    isOn: Binding(
                        get: { reminderPreferencesController.reminderPreferences.globalReminderEnabled },
                        set: { isEnabled in
                            Task {
                                await reminderPreferencesController.setGlobalReminderEnabled(isEnabled)
                            }
                        }
                    )
                )
                .disabled(isReminderPreferenceEditingDisabled)

                Toggle(
                    "静音模式",
                    isOn: Binding(
                        get: { reminderPreferencesController.reminderPreferences.isMuted },
                        set: { isMuted in
                            Task {
                                await reminderPreferencesController.setMuted(isMuted)
                            }
                        }
                    )
                )
                .disabled(isReminderPreferenceEditingDisabled)

                Toggle(
                    "仅在耳机连接时播放提醒音频",
                    isOn: Binding(
                        get: { reminderPreferencesController.reminderPreferences.playSoundOnlyWhenHeadphonesConnected },
                        set: { isEnabled in
                            Task {
                                await reminderPreferencesController.setPlaySoundOnlyWhenHeadphonesConnected(isEnabled)
                            }
                        }
                    )
                )
                .disabled(isReminderPreferenceEditingDisabled)

                Text("默认关闭。开启后只有在当前默认输出被识别为耳机、蓝牙耳机或其他私密收听设备时才播放音频；否则会静默命中，并保留菜单栏高优先级提醒态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(
                    "仅提醒含视频会议信息的事件",
                    isOn: Binding(
                        get: { reminderPreferencesController.reminderPreferences.onlyForMeetingsWithVideoLink },
                        set: { isEnabled in
                            Task {
                                await reminderPreferencesController.setOnlyForMeetingsWithVideoLink(isEnabled)
                            }
                        }
                    )
                )
                .disabled(isReminderPreferenceEditingDisabled)

                Toggle(
                    "跳过已拒绝会议",
                    isOn: Binding(
                        get: { reminderPreferencesController.reminderPreferences.skipDeclinedMeetings },
                        set: { isEnabled in
                            Task {
                                await reminderPreferencesController.setSkipDeclinedMeetings(isEnabled)
                            }
                        }
                    )
                )
                .disabled(isReminderPreferenceEditingDisabled)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("提醒音频")
                            .font(.caption.weight(.medium))

                        Spacer()

                        if soundProfileLibraryController.isLoadingState
                            || soundProfileLibraryController.isImportingState
                            || soundProfileLibraryController.isApplyingState {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Button {
                            isPresentingSoundImporter = true
                        } label: {
                            Label("上传音频", systemImage: "square.and.arrow.down")
                        }
                        .disabled(isSoundProfileEditingDisabled)
                    }

                    if let selectedSoundProfile = soundProfileLibraryController.selectedSoundProfile {
                        Text("当前使用：\(selectedSoundProfile.displayName) · \(selectedSoundProfile.durationLine)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("支持一次选择多个音频文件，也可以后续继续追加上传。列表里的任一音频都可以试听并切换为正式提醒音频。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(soundProfileLibraryController.soundProfiles) { soundProfile in
                            soundProfileRow(for: soundProfile)
                        }
                    }

                    if let lastErrorMessage = soundProfileLibraryController.lastErrorMessage {
                        Text(lastErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("倒计时秒数覆盖")
                        .font(.caption.weight(.medium))

                    if let overrideSeconds = reminderPreferencesController.reminderPreferences.countdownOverrideSeconds {
                        Stepper(
                            value: Binding(
                                get: { overrideSeconds },
                                set: { newValue in
                                    Task {
                                        await reminderPreferencesController.setCountdownOverrideSeconds(newValue)
                                    }
                                }
                            ),
                            in: 1 ... 300
                        ) {
                            Text("当前手动设为 \(overrideSeconds) 秒")
                        }
                        .disabled(isReminderPreferenceEditingDisabled)

                        Button {
                            Task {
                                await reminderPreferencesController.setCountdownOverrideSeconds(nil)
                            }
                        } label: {
                            Label("改回跟随当前提醒音频时长", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(isReminderPreferenceEditingDisabled)
                    } else {
                        if let selectedSoundProfile = soundProfileLibraryController.selectedSoundProfile {
                            Text("当前跟随 \(selectedSoundProfile.displayName) 的时长（\(selectedSoundProfile.durationLine)）。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("当前跟随默认提醒音效时长。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("如果你不手动覆盖秒数，提醒会按当前选中的音频时长自动计算。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            Task {
                                await reminderPreferencesController.setCountdownOverrideSeconds(10)
                            }
                        } label: {
                            Label("改为手动 10 秒", systemImage: "timer")
                        }
                        .disabled(isReminderPreferenceEditingDisabled)
                    }
                }

                if let lastErrorMessage = reminderPreferencesController.lastErrorMessage {
                    Text(lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 把同步新鲜度和开机启动这些系统级运行策略收口到同一块。
    @ViewBuilder
    private var syncAndIntegrationGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("同步与系统集成")
                        .font(.headline)

                    Spacer()

                    badge(
                        text: syncFreshnessStatus.badgeText,
                        color: diagnosticBadgeColor(for: syncFreshnessStatus)
                    )
                }

                LabeledContent("最近成功读取", value: sourceCoordinator.lastRefreshLine)

                Text(syncFreshnessStatus.summary)
                    .font(.caption)
                    .foregroundStyle(syncFreshnessTextColor(for: syncFreshnessStatus))

                Text("这里展示的是 app 最近一次成功读取本地系统日历的时间，不等同于飞书远端实时同步状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle(
                    "登录后自动启动",
                    isOn: Binding(
                        get: { launchAtLoginController.isEnabled },
                        set: { isEnabled in
                            Task {
                                await launchAtLoginController.setEnabled(isEnabled)
                            }
                        }
                    )
                )
                .disabled(launchAtLoginController.isApplyingState)

                Text(launchAtLoginController.statusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let lastErrorMessage = launchAtLoginController.lastErrorMessage {
                    Text(lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 单条系统日历候选行，展示推荐标记、来源说明和可勾选状态。
    @ViewBuilder
    private func calendarRow(for calendar: SystemCalendarDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Toggle(
                    isOn: Binding(
                        get: {
                            systemCalendarConnectionController.selectedCalendarIDs.contains(calendar.id)
                        },
                        set: { isSelected in
                            Task {
                                await systemCalendarConnectionController.setCalendarSelection(
                                    calendarID: calendar.id,
                                    isSelected: isSelected
                                )
                            }
                        }
                    )
                ) {
                    Text(calendar.title)
                        .font(.body.weight(.medium))
                }
                .toggleStyle(.checkbox)

                if calendar.isSuggestedByDefault {
                    badge(text: "推荐", color: .green)
                }
            }

            Text(calendar.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    /// 单条提醒音频的列表行，提供“切换当前音频”“试听”和“删除”能力。
    @ViewBuilder
    private func soundProfileRow(for soundProfile: SoundProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(soundProfile.displayName)
                            .font(.body.weight(.medium))

                        if soundProfile.isBundledDefault {
                            badge(text: "内建", color: .secondary)
                        }

                        if soundProfile.id == soundProfileLibraryController.selectedSoundProfileID {
                            badge(text: "当前使用中", color: .blue)
                        }
                    }

                    Text(soundProfile.durationLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task {
                        await soundProfileLibraryController.togglePreview(for: soundProfile.id)
                    }
                } label: {
                    Label(
                        soundProfileLibraryController.currentlyPreviewingSoundProfileID == soundProfile.id ? "停止" : "播放",
                        systemImage: soundProfileLibraryController.currentlyPreviewingSoundProfileID == soundProfile.id
                            ? "stop.circle"
                            : "play.circle"
                    )
                }
                .disabled(soundProfileLibraryController.isLoadingState)

                if soundProfile.id != soundProfileLibraryController.selectedSoundProfileID {
                    Button {
                        Task {
                            await soundProfileLibraryController.selectSoundProfile(id: soundProfile.id)
                        }
                    } label: {
                        Label("使用", systemImage: "checkmark.circle")
                    }
                    .disabled(isSoundProfileEditingDisabled)
                }

                if soundProfile.isImported {
                    Button(role: .destructive) {
                        Task {
                            await soundProfileLibraryController.deleteSoundProfile(id: soundProfile.id)
                        }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .disabled(isSoundProfileEditingDisabled)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    /// 授权状态标签使用更贴近日历流程的颜色。
    private func authorizationBadgeColor(for state: SystemCalendarAuthorizationState) -> Color {
        switch state {
        case .authorized:
            return .green
        case .notDetermined:
            return .orange
        case .denied, .restricted, .writeOnly:
            return .red
        case .unknown:
            return .secondary
        }
    }

    /// 同步新鲜度诊断沿用统一的 `DiagnosticCheckStatus` 颜色语义。
    private func diagnosticBadgeColor(for status: DiagnosticCheckStatus) -> Color {
        switch status {
        case .passed:
            return .green
        case .warning:
            return .orange
        case .failed:
            return .red
        case .idle, .pending:
            return .secondary
        }
    }

    /// 详细文案用较轻的颜色表达，warning / failed 则适度强调。
    private func syncFreshnessTextColor(for status: DiagnosticCheckStatus) -> Color {
        switch status {
        case .passed, .idle, .pending:
            return .secondary
        case .warning:
            return .orange
        case .failed:
            return .red
        }
    }

    /// 给单色标签提供一个更轻量的通用渲染入口。
    @ViewBuilder
    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.18))
            )
            .foregroundStyle(color)
    }

    /// 打开 macOS 隐私设置里的日历权限页，帮助用户修复已拒绝的状态。
    private func openCalendarPrivacySettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }

    /// 设置页复用的绝对时间格式。
    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// 统一控制提醒偏好编辑区的禁用条件。
    private var isReminderPreferenceEditingDisabled: Bool {
        reminderPreferencesController.isLoadingState || reminderPreferencesController.isSavingState
    }

    /// 音频列表编辑和切换的禁用条件。
    private var isSoundProfileEditingDisabled: Bool {
        soundProfileLibraryController.isLoadingState
            || soundProfileLibraryController.isImportingState
            || soundProfileLibraryController.isApplyingState
    }

    /// 设置页使用的本地同步新鲜度摘要。
    private var syncFreshnessStatus: DiagnosticCheckStatus {
        SyncFreshnessDiagnostic.status(
            lastSuccessfulRefreshAt: sourceCoordinator.state.lastRefreshAt,
            now: Date()
        )
    }
}
