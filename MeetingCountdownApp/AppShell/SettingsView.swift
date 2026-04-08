import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// `SettingsView` 现在围绕“先看摘要、再完成接入、最后调整策略”的阅读顺序组织。
/// 它依旧只消费聚合状态，但不再把所有内容平铺成一页技术说明，
/// 而是尽量把用户最关心的“现在是否连上了、下一步做什么”放到前面。
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
            VStack(alignment: .leading, spacing: 22) {
                overviewGroup
                setupAndCalendarGroup
                reminderPreferencesGroup
                syncAndIntegrationGroup
                diagnosticsAndRuntimeGroup
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
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

    /// 顶部摘要区先给出 4 个最关键答案：
    /// 接入是否完成、已选几个日历、下一场会议是什么、提醒是否真正就绪。
    @ViewBuilder
    private var overviewGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    title: "当前总览",
                    subtitle: "先看这 4 个状态，就能知道 app 现在是否已经准备好提醒。"
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12, alignment: .leading),
                        GridItem(.flexible(), spacing: 12, alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: 12
                ) {
                    summaryCard(
                        title: "连接状态",
                        value: systemCalendarConnectionController.authorizationState.badgeText,
                        detail: systemCalendarConnectionController.authorizationState.summary,
                        badgeText: systemCalendarConnectionController.authorizationState.badgeText,
                        badgeColor: authorizationBadgeColor(for: systemCalendarConnectionController.authorizationState)
                    )

                    summaryCard(
                        title: "已选日历",
                        value: systemCalendarConnectionController.selectionSummary,
                        detail: selectedCalendarDetailLine,
                        badgeText: systemCalendarConnectionController.hasSelectedCalendars ? "已完成" : "待处理",
                        badgeColor: systemCalendarConnectionController.hasSelectedCalendars ? .green : .orange
                    )

                    summaryCard(
                        title: "下一场会议",
                        value: nextMeetingValueLine,
                        detail: nextMeetingDetailLine,
                        badgeText: sourceCoordinator.state.nextMeeting == nil ? "暂无" : "已锁定",
                        badgeColor: sourceCoordinator.state.nextMeeting == nil ? .secondary : .blue
                    )

                    summaryCard(
                        title: "提醒状态",
                        value: reminderEngine.state.summary,
                        detail: reminderEngine.state.detailLine,
                        badgeText: reminderStatusBadgeText,
                        badgeColor: reminderStatusBadgeColor
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 接入与权限区把“唯一接入路径”与真实配置动作合并到一起，
    /// 让用户不必在说明块和配置块之间来回切换上下文。
    @ViewBuilder
    private var setupAndCalendarGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    sectionHeader(
                        title: "接入与权限",
                        subtitle: "沿着 `飞书 CalDAV -> macOS 日历 -> 本 app` 这条路径完成配置。"
                    )

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
                }

                VStack(alignment: .leading, spacing: 8) {
                    setupStepRow(
                        title: "在飞书里生成 CalDAV 配置",
                        detail: "复制用户名、专用密码和服务器地址。",
                        isComplete: true
                    )
                    setupStepRow(
                        title: "在 macOS“日历”里添加 Other CalDAV Account",
                        detail: "账户类型选择“手动”，再把飞书提供的配置粘贴进去。",
                        isComplete: systemCalendarConnectionController.authorizationState == .authorized || !systemCalendarConnectionController.availableCalendars.isEmpty
                    )
                    setupStepRow(
                        title: "授权本 app 读取系统日历",
                        detail: systemCalendarConnectionController.authorizationState.summary,
                        isComplete: systemCalendarConnectionController.authorizationState == .authorized
                    )
                    setupStepRow(
                        title: "勾选要纳入提醒的飞书日历",
                        detail: systemCalendarConnectionController.selectionSummary,
                        isComplete: systemCalendarConnectionController.hasSelectedCalendars
                    )
                }

                Divider()

                HStack(spacing: 10) {
                    badge(
                        text: systemCalendarConnectionController.authorizationState.badgeText,
                        color: authorizationBadgeColor(for: systemCalendarConnectionController.authorizationState)
                    )

                    if let lastLoadedAt = systemCalendarConnectionController.lastLoadedAt {
                        Text("最近检查：\(Self.absoluteFormatter.string(from: lastLoadedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastErrorMessage = systemCalendarConnectionController.lastErrorMessage {
                    Text(lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                switch systemCalendarConnectionController.authorizationState {
                case .authorized:
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("当前选择", value: systemCalendarConnectionController.selectionSummary)

                        if systemCalendarConnectionController.isLoadingState {
                            ProgressView("正在读取系统日历…")
                                .controlSize(.small)
                        } else if systemCalendarConnectionController.availableCalendars.isEmpty {
                            Text("当前还没有可读取的系统日历。请先确认飞书 CalDAV 已经成功同步到 macOS“日历”应用。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(systemCalendarConnectionController.availableCalendars) { calendar in
                                    calendarRow(for: calendar)
                                }
                            }
                        }
                    }

                case .notDetermined:
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            Task {
                                await systemCalendarConnectionController.requestCalendarAccess()
                            }
                        } label: {
                            Label("授权访问日历", systemImage: "calendar.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(systemCalendarConnectionController.isRequestingAccess)

                        Text("只有在你点击按钮后，系统才会弹出 Calendar 权限请求。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                case .denied, .restricted, .writeOnly, .unknown:
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            openCalendarPrivacySettings()
                        } label: {
                            Label("打开系统设置修复权限", systemImage: "gearshape")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Text("修复权限后回到这里重新检查，再选择真正要纳入提醒的系统日历。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 提醒偏好区仍保留全部核心能力，但按“基础提醒 / 会议筛选 / 音频与倒计时”分层。
    @ViewBuilder
    private var reminderPreferencesGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    sectionHeader(
                        title: "提醒",
                        subtitle: "先决定提醒是否启用，再收紧筛选规则和音频策略。"
                    )

                    Spacer()

                    if reminderPreferencesController.isLoadingState || reminderPreferencesController.isSavingState {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                preferenceSubsection(title: "基础提醒") {
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

                    Text("开启后，默认输出只有在被识别为耳机或私密收听设备时才会播放提醒音频。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                preferenceSubsection(title: "会议筛选") {
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
                }

                preferenceSubsection(title: "音频与倒计时") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(currentSoundProfileLine)
                                    .font(.callout.weight(.medium))

                                Text("支持一次导入多个音频；可随时试听，并把某个音频切换为正式提醒音效。")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

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

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(soundProfileLibraryController.soundProfiles) { soundProfile in
                                soundProfileRow(for: soundProfile)
                            }
                        }

                        countdownOverrideSection

                        if let lastErrorMessage = soundProfileLibraryController.lastErrorMessage {
                            Text(lastErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
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

    /// 同步与系统集成只放“最近是否读到日历”和“是否登录启动”这两类运行策略。
    @ViewBuilder
    private var syncAndIntegrationGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    sectionHeader(
                        title: "同步与系统集成",
                        subtitle: "这里展示本 app 最近一次读取系统日历的结果，不代表飞书远端一定已经同步。"
                    )

                    Spacer()

                    badge(
                        text: syncFreshnessStatus.badgeText,
                        color: diagnosticBadgeColor(for: syncFreshnessStatus)
                    )
                }

                LabeledContent("最近成功读取", value: sourceCoordinator.lastRefreshLine)

                Text(syncFreshnessStatus.summary)
                    .font(.callout)
                    .foregroundStyle(syncFreshnessTextColor(for: syncFreshnessStatus))

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
                    .font(.callout)
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

    /// 诊断与运行态细节被放到最后，避免一打开设置就像在读后台面板。
    @ViewBuilder
    private var diagnosticsAndRuntimeGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    sectionHeader(
                        title: "高级与诊断",
                        subtitle: "如果你想确认源健康度、提醒调度和错误信息，再看这一块。"
                    )

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

                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("活动数据源", value: "CalDAV / 系统日历")
                    LabeledContent("健康状态", value: sourceCoordinator.state.healthState.summary)
                    LabeledContent("提醒状态", value: reminderEngine.state.summary)
                }

                Text(reminderEngine.state.detailLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let lastErrorMessage = sourceCoordinator.state.lastErrorMessage {
                    Text(lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 音频倒计时覆盖区保留原有逻辑，但拉成单独的小节，避免和音频列表混成一片。
    @ViewBuilder
    private var countdownOverrideSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("倒计时秒数")
                .font(.callout.weight(.medium))

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
                Text(countdownFollowLine)
                    .font(.callout)
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
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    /// 单条提醒音频的列表行，保留试听能力，把次要和破坏性动作收进尾部菜单。
    @ViewBuilder
    private func soundProfileRow(for soundProfile: SoundProfile) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
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
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await soundProfileLibraryController.togglePreview(for: soundProfile.id)
                }
            } label: {
                Label(
                    soundProfileLibraryController.currentlyPreviewingSoundProfileID == soundProfile.id ? "停止试听" : "试听",
                    systemImage: soundProfileLibraryController.currentlyPreviewingSoundProfileID == soundProfile.id
                        ? "stop.circle"
                        : "play.circle"
                )
            }
            .disabled(soundProfileLibraryController.isLoadingState)

            Menu {
                if soundProfile.id != soundProfileLibraryController.selectedSoundProfileID {
                    Button {
                        Task {
                            await soundProfileLibraryController.selectSoundProfile(id: soundProfile.id)
                        }
                    } label: {
                        Label("设为当前提醒音频", systemImage: "checkmark.circle")
                    }
                }

                if soundProfile.isImported {
                    Button(role: .destructive) {
                        Task {
                            await soundProfileLibraryController.deleteSoundProfile(id: soundProfile.id)
                        }
                    } label: {
                        Label("删除音频", systemImage: "trash")
                    }
                }
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
            .disabled(isSoundProfileEditingDisabled)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    /// 统一 section 标题样式，拉开“标题 / 说明 / 控件”的层级。
    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// 统一设置页小节排版。
    @ViewBuilder
    private func preferenceSubsection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.callout.weight(.medium))

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 顶部摘要卡。
    @ViewBuilder
    private func summaryCard(
        title: String,
        value: String,
        detail: String,
        badgeText: String,
        badgeColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                badge(text: badgeText, color: badgeColor)
            }

            Text(value)
                .font(.body.weight(.semibold))
                .lineLimit(2)

            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    /// Setup checklist 行。
    @ViewBuilder
    private func setupStepRow(title: String, detail: String, isComplete: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? Color.green : Color.secondary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.medium))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

    /// 摘要区里的已选日历补充信息。
    private var selectedCalendarDetailLine: String {
        if systemCalendarConnectionController.hasSelectedCalendars {
            return "你当前勾选的系统日历会一起参与“下一场会议”计算。"
        }

        return "还没有选中任何系统日历，因此提醒链路还不能真正生效。"
    }

    /// 摘要区里的下一场会议主值。
    private var nextMeetingValueLine: String {
        if let nextMeeting = sourceCoordinator.state.nextMeeting {
            return nextMeeting.title
        }

        return "当前暂无可提醒会议"
    }

    /// 摘要区里的下一场会议补充说明。
    private var nextMeetingDetailLine: String {
        if let nextMeeting = sourceCoordinator.state.nextMeeting {
            return sourceCoordinator.meetingStartLine(for: nextMeeting)
        }

        return sourceCoordinator.detailLine
    }

    /// 摘要区里的提醒状态标签。
    private var reminderStatusBadgeText: String {
        switch reminderEngine.state {
        case .disabled:
            return "已关闭"
        case .failed:
            return "异常"
        case .idle:
            return "待命"
        case .scheduled:
            return "已安排"
        case .playing, .triggeredSilently:
            return "进行中"
        }
    }

    /// 摘要区里的提醒状态颜色。
    private var reminderStatusBadgeColor: Color {
        switch reminderEngine.state {
        case .disabled:
            return .secondary
        case .failed:
            return .red
        case .idle:
            return .orange
        case .scheduled:
            return .green
        case .playing, .triggeredSilently:
            return .blue
        }
    }

    /// 当前音频摘要行。
    private var currentSoundProfileLine: String {
        if let selectedSoundProfile = soundProfileLibraryController.selectedSoundProfile {
            return "当前提醒音频：\(selectedSoundProfile.displayName) · \(selectedSoundProfile.durationLine)"
        }

        return "当前提醒音频：默认提醒音效"
    }

    /// 当前倒计时说明。
    private var countdownFollowLine: String {
        if let selectedSoundProfile = soundProfileLibraryController.selectedSoundProfile {
            return "当前跟随 \(selectedSoundProfile.displayName) 的时长（\(selectedSoundProfile.durationLine)）。"
        }

        return "当前跟随默认提醒音效时长。"
    }
}
