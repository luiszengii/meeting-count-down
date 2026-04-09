import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// `SettingsView` 改成“标题 + pill tab + 玻璃卡片”的结构。
/// 现有设置项和状态仍保持不变，只重组到更接近控制中心灵感的页面里。
struct SettingsView: View {
    @ObservedObject var sourceCoordinator: SourceCoordinator
    @ObservedObject var systemCalendarConnectionController: SystemCalendarConnectionController
    @ObservedObject var reminderEngine: ReminderEngine
    @ObservedObject var reminderPreferencesController: ReminderPreferencesController
    @ObservedObject var soundProfileLibraryController: SoundProfileLibraryController
    @ObservedObject var launchAtLoginController: LaunchAtLoginController

    @State private var isPresentingSoundImporter = false
    @State private var selectedTab: SettingsTab = .overview
    @State private var isCalendarConfigurationExpanded = true
    @State private var hasInitializedCalendarConfigurationExpansion = false
    @State private var hoveredSoundProfileID: SoundProfile.ID?

    var body: some View {
        ZStack {
            GlassBackdrop()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    tabBar
                    tabContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            guard !hasInitializedCalendarConfigurationExpansion else {
                return
            }

            hasInitializedCalendarConfigurationExpansion = true
            isCalendarConfigurationExpanded = !isCalendarConfigurationComplete
        }
        .onChange(of: isCalendarConfigurationComplete) { _, isComplete in
            withAnimation(GlassMotion.page) {
                isCalendarConfigurationExpanded = !isComplete
            }
        }
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

    /// 顶部标题区负责先建立“这是一套重新设计过的控制中心式设置页”。
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("会议倒计时设置", "Countdown Settings"))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.96))

            Text(localized("集中管理日历接入、提醒行为、音频和诊断状态，不改变现有业务逻辑。", "Manage calendar access, reminder behavior, audio, and diagnostic state without changing the current business logic."))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 560, alignment: .leading)
        }
    }

    /// tab 导航把原本一张长滚动页拆成五个固定主题，减少信息拥挤。
    private var tabBar: some View {
        GlassSegmentedTabs(selection: $selectedTab) { tab in
            tab.title(for: uiLanguage)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var tabContent: some View {
        ZStack(alignment: .topLeading) {
            if selectedTab == .overview {
                overviewPage
                    .transition(.settingsPageSwap)
            }

            if selectedTab == .calendar {
                calendarPage
                    .transition(.settingsPageSwap)
            }

            if selectedTab == .reminders {
                remindersPage
                    .transition(.settingsPageSwap)
            }

            if selectedTab == .audio {
                audioPage
                    .transition(.settingsPageSwap)
            }

            if selectedTab == .advanced {
                advancedPage
                    .transition(.settingsPageSwap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(GlassMotion.page, value: selectedTab)
    }

    /// Overview 页优先回答当前系统是否健康、下一场会议是什么、提醒是否真的在工作。
    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let nextMeeting = sourceCoordinator.state.nextMeeting {
                GlassPanel(cornerRadius: 24, padding: 18, overlayOpacity: 0.16) {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionEyebrow(localized("下一场会议", "NEXT MEETING"))

                        ViewThatFits(in: .horizontal) {
                            nextMeetingCardContent(for: nextMeeting, compactLayout: false)
                            nextMeetingCardContent(for: nextMeeting, compactLayout: true)
                        }
                    }
                }
            }

            overviewMetrics
        }
    }

    /// Overview 里的下一场会议卡在较窄宽度下需要允许主按钮换到下一行。
    @ViewBuilder
    private func nextMeetingCardContent(for nextMeeting: MeetingRecord, compactLayout: Bool) -> some View {
        if compactLayout {
            VStack(alignment: .leading, spacing: 14) {
                nextMeetingCardPrimaryInfo(for: nextMeeting)

                if let meetingURL = nextMeeting.links.first?.url {
                    Button {
                        NSWorkspace.shared.open(meetingURL)
                    } label: {
                        Text(localizedJoinActionTitle(for: nextMeeting))
                    }
                    .buttonStyle(GlassPillButtonStyle(tone: .primary))
                }
            }
        } else {
            HStack(alignment: .center, spacing: 18) {
                nextMeetingCardPrimaryInfo(for: nextMeeting)

                Spacer()

                if let meetingURL = nextMeeting.links.first?.url {
                    Button {
                        NSWorkspace.shared.open(meetingURL)
                    } label: {
                        Text(localizedJoinActionTitle(for: nextMeeting))
                    }
                    .buttonStyle(GlassPillButtonStyle(tone: .primary))
                }
            }
        }
    }

    private func nextMeetingCardPrimaryInfo(for nextMeeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(nextMeeting.title)
                .font(.system(size: 20, weight: .bold))
                .lineLimit(2)

            Text(localizedMeetingStartLine(for: nextMeeting))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                GlassBadge(text: nextMeeting.source.displayName, color: .blue)

                if nextMeeting.hasVideoConferenceLink {
                    GlassBadge(text: localized("视频会议", "Video Link"), color: .green)
                }
            }
        }
    }

    /// Calendar 页承接唯一支持的接入路径，不改原有权限和多选逻辑，只改布局。
    private var calendarPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            GlassPanel(cornerRadius: 24, padding: 18, overlayOpacity: 0.14) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionEyebrow(localized("日历配置", "CALENDAR CONFIGURATION"))

                            Text(localized("自动同步飞书 CalDAV", "Auto-sync Feishu CalDAV"))
                                .font(.system(size: 19, weight: .bold))

                            Text(calendarConfigurationSummaryLine)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 10) {
                            GlassBadge(
                                text: isCalendarConfigurationComplete
                                    ? localized("已完成", "Complete")
                                    : localized("待处理", "Needs Setup"),
                                color: isCalendarConfigurationComplete ? .green : .orange
                            )

                            HStack(spacing: 10) {
                                if isCalendarConfigurationComplete {
                                    Button {
                                        withAnimation(GlassMotion.page) {
                                            isCalendarConfigurationExpanded.toggle()
                                        }
                                    } label: {
                                        Text(isCalendarConfigurationExpanded
                                            ? localized("收起步骤", "Hide Steps")
                                            : localized("查看步骤", "View Steps"))
                                    }
                                    .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                                }

                                Button {
                                    Task {
                                        await systemCalendarConnectionController.refreshState()
                                        await sourceCoordinator.refresh(trigger: .manualRefresh)
                                    }
                                } label: {
                                    Text(localized("重新检查", "Re-check"))
                                }
                                .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                                .disabled(systemCalendarConnectionController.isLoadingState || systemCalendarConnectionController.isRequestingAccess)
                            }
                        }
                    }

                    if !isCalendarConfigurationComplete || isCalendarConfigurationExpanded {
                        VStack(alignment: .leading, spacing: 10) {
                            setupStepRow(
                                title: localized("在飞书里生成 CalDAV 凭证", "Generate CalDAV credentials in Feishu"),
                                detail: localized("复制用户名、专用密码和服务器地址。", "Copy username, app-specific password, and server address."),
                                isComplete: true
                            )
                            setupStepRow(
                                title: localized("在 macOS 日历里添加“其他 CalDAV 账户”", "Add an Other CalDAV Account in macOS Calendar"),
                                detail: localized("选择“手动”，再粘贴飞书提供的凭证。", "Choose manual setup, then paste the Feishu credentials."),
                                isComplete: hasAddedCalDAVAccount
                            )
                            setupStepRow(
                                title: localized("授予本应用日历访问权限", "Grant this app calendar access"),
                                detail: localizedAuthorizationSummary(for: systemCalendarConnectionController.authorizationState),
                                isComplete: systemCalendarConnectionController.authorizationState == .authorized
                            )
                            setupStepRow(
                                title: localized("选择需要参与提醒的日历", "Select the calendars that should count"),
                                detail: localizedCalendarSelectionSummary,
                                isComplete: systemCalendarConnectionController.hasSelectedCalendars
                            )
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }

            GlassPanel(cornerRadius: 24, padding: 18, overlayOpacity: 0.14) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        sectionEyebrow(localized("本地日历源", "LOCAL CALENDAR SOURCE"))

                        Spacer()

                        GlassBadge(
                            text: localizedAuthorizationBadgeText(for: systemCalendarConnectionController.authorizationState),
                            color: authorizationBadgeColor(for: systemCalendarConnectionController.authorizationState)
                        )
                    }

                    if let lastLoadedAt = systemCalendarConnectionController.lastLoadedAt {
                        Text("\(localized("最近检查时间", "Last checked")): \(Self.absoluteFormatter.string(from: lastLoadedAt))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    if let lastErrorMessage = systemCalendarConnectionController.lastErrorMessage {
                        Text(lastErrorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red)
                    }

                    switch systemCalendarConnectionController.authorizationState {
                    case .authorized:
                        if systemCalendarConnectionController.isLoadingState {
                            ProgressView(localized("正在读取本地日历…", "Reading local calendars..."))
                                .controlSize(.small)
                        } else if systemCalendarConnectionController.availableCalendars.isEmpty {
                            Text(localized("当前还没有可读取的系统日历。请先确认飞书 CalDAV 已经成功同步到 macOS“日历”应用。", "No readable calendars are currently available. Confirm that Feishu CalDAV has already synced into the macOS Calendar app."))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(
                                columns: responsiveCardColumns(minimum: 260),
                                spacing: 16
                            ) {
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
                            Label(localized("授予日历权限", "Grant Calendar Access"), systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(GlassPillButtonStyle(tone: .primary))
                        .disabled(systemCalendarConnectionController.isRequestingAccess)

                    case .denied, .restricted, .writeOnly, .unknown:
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                openCalendarPrivacySettings()
                            } label: {
                                Text(localized("打开系统设置", "Open System Settings"))
                            }
                            .buttonStyle(GlassPillButtonStyle(tone: .primary))

                            Text(localized("先修复权限问题，再回来重新检查本地日历源。", "Repair the permission first, then come back and re-check the local calendar source."))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// Reminders 页保留全部布尔偏好，但切成大卡片开关，贴近参考图中的模块块感。
    private var remindersPage: some View {
        GlassPanel(cornerRadius: 24, padding: 18, overlayOpacity: 0.14) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    sectionEyebrow(localized("提醒策略", "REMINDER POLICY"))

                    Spacer()

                    if reminderPreferencesController.isLoadingState || reminderPreferencesController.isSavingState {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                reminderToggleCard(
                    title: localized("启用本地提醒", "Enable Local Reminders"),
                    detail: localized("为已选日历创建会前提醒任务。", "Create the scheduled pre-meeting reminder for the selected calendars."),
                    isOn: Binding(
                        get: { reminderPreferencesController.reminderPreferences.globalReminderEnabled },
                        set: { isEnabled in
                            Task {
                                await reminderPreferencesController.setGlobalReminderEnabled(isEnabled)
                            }
                        }
                    )
                )

                reminderToggleCard(
                    title: localized("静音模式", "Mute Mode"),
                    detail: localized("保留提醒调度，但跳过音频播放。", "Keep reminder scheduling active, but skip audio playback."),
                    isOn: Binding(
                        get: { reminderPreferencesController.reminderPreferences.isMuted },
                        set: { isMuted in
                            Task {
                                await reminderPreferencesController.setMuted(isMuted)
                            }
                        }
                    )
                )

                reminderToggleCard(
                    title: localized("仅在耳机连接时播放", "Play Sound Only When Headphones Are Connected"),
                    detail: localized("如果当前输出无法被识别为私密收听设备，本次提醒会保持静默。", "If the output route is not recognized as private listening, the reminder stays silent."),
                    isOn: Binding(
                        get: { reminderPreferencesController.reminderPreferences.playSoundOnlyWhenHeadphonesConnected },
                        set: { isEnabled in
                            Task {
                                await reminderPreferencesController.setPlaySoundOnlyWhenHeadphonesConnected(isEnabled)
                            }
                        }
                    )
                )

                reminderToggleCard(
                    title: localized("仅提醒含视频链接的会议", "Only Remind for Meetings with Video Link"),
                    detail: localized("只对检测到视频会议链接的事件参与“下一场会议”计算。", "Filter the next-meeting calculation to events containing a detected video conference link."),
                    isOn: Binding(
                        get: { reminderPreferencesController.reminderPreferences.onlyForMeetingsWithVideoLink },
                        set: { isEnabled in
                            Task {
                                await reminderPreferencesController.setOnlyForMeetingsWithVideoLink(isEnabled)
                            }
                        }
                    )
                )

                reminderToggleCard(
                    title: localized("跳过已拒绝会议", "Skip Declined Meetings"),
                    detail: localized("忽略当前用户已明确拒绝的会议。", "Ignore meetings the current user has explicitly declined."),
                    isOn: Binding(
                        get: { reminderPreferencesController.reminderPreferences.skipDeclinedMeetings },
                        set: { isEnabled in
                            Task {
                                await reminderPreferencesController.setSkipDeclinedMeetings(isEnabled)
                            }
                        }
                    )
                )

                if let lastErrorMessage = reminderPreferencesController.lastErrorMessage {
                    Text(lastErrorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    /// Audio 页继续保留上传、试听、切换和删除，只把列表改成玻璃卡片栅格。
    private var audioPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            GlassPanel(cornerRadius: 24, padding: 18, overlayOpacity: 0.14) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionEyebrow(localized("音频", "AUDIO"))
                            Text(currentSoundProfileLine)
                                .font(.system(size: 17, weight: .bold))
                            Text(localized("导入一个或多个提醒音频，试听它们，并选择哪一条用于驱动提醒倒计时。", "Import one or more sounds, preview them, and choose which one should drive the reminder countdown."))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            isPresentingSoundImporter = true
                        } label: {
                            Text(localized("上传音频", "Upload Audio"))
                        }
                        .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                        .disabled(isSoundProfileEditingDisabled)
                    }

                    LazyVGrid(
                        columns: responsiveCardColumns(minimum: 280),
                        spacing: 16
                    ) {
                        ForEach(soundProfileLibraryController.soundProfiles) { soundProfile in
                            soundProfileRow(for: soundProfile)
                        }
                    }

                    countdownOverrideSection

                    if let lastErrorMessage = soundProfileLibraryController.lastErrorMessage {
                        Text(lastErrorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    /// Advanced 页承载原本零散的同步、开机启动和诊断信息，避免 Overview 继续变成调试面板。
    private var advancedPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            GlassPanel(cornerRadius: 24, padding: 18, overlayOpacity: 0.14) {
                VStack(alignment: .leading, spacing: 18) {
                    sectionEyebrow(localized("语言", "LANGUAGE"))

                    Text(localized("切换后会统一设置页、菜单栏弹层和状态栏文案。", "Switching updates the Settings window, popover, and status-item copy together."))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    GlassSegmentedTabs(selection: interfaceLanguageBinding) { language in
                        language.optionLabel
                    }
                    .frame(maxWidth: 280, alignment: .leading)
                }
            }

            GlassPanel(cornerRadius: 24, padding: 18, overlayOpacity: 0.14) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        sectionEyebrow(localized("同步", "SYNC"))
                        Spacer()
                        GlassBadge(text: localizedSyncFreshnessBadgeText, color: diagnosticBadgeColor(for: syncFreshnessStatus))
                    }

                    infoRow(title: localized("最近成功读取", "Last Successful Read"), value: localizedLastRefreshLine)
                    infoRow(title: localized("新鲜度摘要", "Freshness Summary"), value: localizedSyncFreshnessSummary)

                    Toggle(
                        localized("开机启动", "Launch at Login"),
                        isOn: Binding(
                            get: { launchAtLoginController.isEnabled },
                            set: { isEnabled in
                                Task {
                                    await launchAtLoginController.setEnabled(isEnabled)
                                }
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .disabled(launchAtLoginController.isApplyingState)

                    Text(localizedLaunchAtLoginStatusSummary)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)

                    if let lastErrorMessage = launchAtLoginController.lastErrorMessage {
                        Text(lastErrorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red)
                    }
                }
            }

            GlassPanel(cornerRadius: 24, padding: 18, overlayOpacity: 0.14) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        sectionEyebrow(localized("诊断", "DIAGNOSTICS"))

                        Spacer()

                        Button {
                            Task {
                                await sourceCoordinator.refresh(trigger: .manualRefresh)
                            }
                        } label: {
                            Text(localized("立即刷新", "Refresh Now"))
                        }
                        .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                        .disabled(sourceCoordinator.state.isRefreshing)
                    }

                    infoRow(title: localized("当前数据源", "Active Data Source"), value: localized("飞书 CalDAV / macOS 日历", "Feishu CalDAV / macOS Calendar"))
                    infoRow(title: localized("健康状态", "Health State"), value: localizedHealthStateSummary)
                    infoRow(title: localized("提醒状态", "Reminder State"), value: localizedReminderStateSummary)

                    Text(localizedReminderStateDetailLine)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)

                    if let lastErrorMessage = sourceCoordinator.state.lastErrorMessage {
                        Text(lastErrorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var overviewMetrics: some View {
        LazyVGrid(
            columns: responsiveCardColumns(minimum: 220, maximum: 320),
            spacing: 18
        ) {
            summaryCard(title: localized("日历权限", "Calendar Access"), value: localizedAuthorizationBadgeText(for: systemCalendarConnectionController.authorizationState), detail: localizedAuthorizationSummary(for: systemCalendarConnectionController.authorizationState), accent: authorizationBadgeColor(for: systemCalendarConnectionController.authorizationState))
            summaryCard(title: localized("生效日历", "Active Calendars"), value: localizedCalendarSelectionSummary, detail: selectedCalendarDetailLine, accent: systemCalendarConnectionController.hasSelectedCalendars ? .green : .orange)
            summaryCard(title: localized("最近同步", "Last Sync"), value: localizedLastRefreshLine, detail: localizedSyncFreshnessSummary, accent: diagnosticBadgeColor(for: syncFreshnessStatus))
            summaryCard(title: localized("应用状态", "App State"), value: sourceCoordinator.state.isRefreshing ? localized("正在刷新…", "Refreshing...") : localizedReminderStateSummary, detail: nextMeetingDetailLine, accent: reminderStatusBadgeColor)
        }
    }

    /// 概览卡统一用大数字/大状态值，减少过去大量小号辅助文案造成的疲劳感。
    private func summaryCard(title: String, value: String, detail: String, accent: Color) -> some View {
        GlassCard(cornerRadius: 24, padding: 18, tintOpacity: 0.2) {
            VStack(alignment: .leading, spacing: 10) {
                Text(uiLanguage == .english ? title.uppercased() : title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent.opacity(0.8))
                    .contentTransition(.opacity)

                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .contentTransition(.opacity)

                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        }
        .animation(GlassMotion.page, value: "\(title)|\(value)|\(detail)")
    }

    /// 开关卡统一用“标题 + 说明 + 右侧 toggle”的方式，保持页面节奏一致。
    private func reminderToggleCard(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        GlassCard(cornerRadius: 24, padding: 20, tintOpacity: 0.2) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))

                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(isReminderPreferenceEditingDisabled)
            }
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 128, alignment: .leading)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.secondary.opacity(0.72))
            .tracking(1.4)
    }

    private func setupStepRow(title: String, detail: String, isComplete: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isComplete ? Color.green : Color.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 系统日历候选保持原有多选语义，但外观改成更像控制中心中的模块卡片。
    private func calendarRow(for calendar: SystemCalendarDescriptor) -> some View {
        GlassCard(cornerRadius: 22, padding: 18, tintOpacity: 0.2) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
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
                            .font(.system(size: 14, weight: .bold))
                    }
                    .toggleStyle(.checkbox)

                    Spacer()

                    if calendar.isSuggestedByDefault {
                        GlassBadge(text: localized("推荐", "Suggested"), color: .green)
                    }
                }

                Text(localizedCalendarSubtitle(for: calendar))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 音频条目把“当前状态”和“动作”拆开，避免重复按钮把列表变得像工具表格。
    private func soundProfileRow(for soundProfile: SoundProfile) -> some View {
        let isCurrent = soundProfile.id == soundProfileLibraryController.selectedSoundProfileID
        let isHovered = hoveredSoundProfileID == soundProfile.id
        let shouldShowMoreMenu = !isCurrent && isHovered

        return GlassCard(cornerRadius: 22, padding: 18, tintOpacity: 0.2) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(soundProfile.displayName)
                            .font(.system(size: 14, weight: .bold))

                        Text(localizedDurationLine(for: soundProfile.duration))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        if soundProfile.isBundledDefault {
                            GlassBadge(text: localized("内建", "Built-in"), color: .secondary)
                        }

                        if isCurrent {
                            GlassBadge(text: localized("当前使用中", "Current"), color: .blue)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await soundProfileLibraryController.togglePreview(for: soundProfile.id)
                        }
                    } label: {
                        Text(soundProfileLibraryController.currentlyPreviewingSoundProfileID == soundProfile.id
                            ? localized("停止试听", "Stop Preview")
                            : localized("试听", "Preview"))
                    }
                    .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                    .disabled(soundProfileLibraryController.isLoadingState)

                    if shouldShowMoreMenu {
                        Menu {
                            Button {
                                Task {
                                    await soundProfileLibraryController.selectSoundProfile(id: soundProfile.id)
                                }
                            } label: {
                                Label(localized("设为当前提醒音频", "Set as Current Reminder"), systemImage: "checkmark.circle")
                            }
                            
                            if soundProfile.isImported {
                                Button(role: .destructive) {
                                    Task {
                                        await soundProfileLibraryController.deleteSoundProfile(id: soundProfile.id)
                                    }
                                } label: {
                                    Label(localized("删除音频", "Delete Audio"), systemImage: "trash")
                                }
                            }
                        } label: {
                            Text(localized("更多", "More"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.18))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .menuStyle(BorderlessButtonMenuStyle())
                        .fixedSize()
                        .disabled(isSoundProfileEditingDisabled)
                        .glassQuietFocus()
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scaleEffect(isHovered ? 1.01 : 1)
        .onHover { isHovering in
            hoveredSoundProfileID = isHovering ? soundProfile.id : (hoveredSoundProfileID == soundProfile.id ? nil : hoveredSoundProfileID)
        }
        .animation(GlassMotion.hover, value: isHovered)
    }

    private var countdownOverrideSection: some View {
        GlassCard(cornerRadius: 24, padding: 18, tintOpacity: 0.18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(localized("倒计时长度", "Countdown Duration"))
                    .font(.system(size: 14, weight: .bold))

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
                        Text(localized("手动倒计时：\(overrideSeconds) 秒", "Manual countdown: \(overrideSeconds) seconds"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .disabled(isReminderPreferenceEditingDisabled)

                    Button {
                        Task {
                            await reminderPreferencesController.setCountdownOverrideSeconds(nil)
                        }
                    } label: {
                        Text(localized("跟随当前音频时长", "Follow Selected Sound Duration"))
                    }
                    .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                    .disabled(isReminderPreferenceEditingDisabled)
                } else {
                    Text(countdownFollowLine)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Button {
                        Task {
                            await reminderPreferencesController.setCountdownOverrideSeconds(10)
                        }
                    } label: {
                        Text(localized("切换为手动 10 秒", "Switch to Manual 10s"))
                    }
                    .buttonStyle(GlassPillButtonStyle(tone: .secondary))
                    .disabled(isReminderPreferenceEditingDisabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

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

    private func openCalendarPrivacySettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private var isReminderPreferenceEditingDisabled: Bool {
        reminderPreferencesController.isLoadingState || reminderPreferencesController.isSavingState
    }

    private var isSoundProfileEditingDisabled: Bool {
        soundProfileLibraryController.isLoadingState
            || soundProfileLibraryController.isImportingState
            || soundProfileLibraryController.isApplyingState
    }

    private var syncFreshnessStatus: DiagnosticCheckStatus {
        SyncFreshnessDiagnostic.status(
            lastSuccessfulRefreshAt: sourceCoordinator.state.lastRefreshAt,
            now: Date()
        )
    }

    private var selectedCalendarDetailLine: String {
        if systemCalendarConnectionController.hasSelectedCalendars {
            return localized("已选日历会参与“下一场会议”计算。", "Selected calendars participate in next-meeting calculation.")
        }

        return localized("当前还没有选中任何日历，因此提醒链路还不会真正生效。", "No calendars are currently selected, so reminders cannot become active.")
    }

    private var nextMeetingDetailLine: String {
        if let nextMeeting = sourceCoordinator.state.nextMeeting {
            return localizedMeetingStartLine(for: nextMeeting)
        }

        return localizedHealthStateSummary
    }

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

    private var currentSoundProfileLine: String {
        if let selectedSoundProfile = soundProfileLibraryController.selectedSoundProfile {
            return "\(selectedSoundProfile.displayName) · \(localizedDurationLine(for: selectedSoundProfile.duration))"
        }

        return localized("默认提醒音效", "Default reminder sound")
    }

    private var countdownFollowLine: String {
        if let selectedSoundProfile = soundProfileLibraryController.selectedSoundProfile {
            let durationLine = localizedDurationLine(for: selectedSoundProfile.duration)
            return localized("当前倒计时跟随 \(selectedSoundProfile.displayName)（\(durationLine)）。", "The countdown currently follows \(selectedSoundProfile.displayName) (\(durationLine)).")
        }

        return localized("当前倒计时跟随默认提醒音效时长。", "The countdown currently follows the default reminder sound duration.")
    }

    /// 当前设置页和菜单栏弹层共用的壳层语言。
    private var uiLanguage: AppUILanguage {
        reminderPreferencesController.reminderPreferences.interfaceLanguage
    }

    /// 语言切换只影响界面文案，不触发业务层重算。
    private var interfaceLanguageBinding: Binding<AppUILanguage> {
        Binding(
            get: { uiLanguage },
            set: { language in
                Task {
                    await reminderPreferencesController.setInterfaceLanguage(language)
                }
            }
        )
    }

    /// 第二项 checklist：是否已经能确认本机存在飞书 CalDAV 账户。
    private var hasAddedCalDAVAccount: Bool {
        systemCalendarConnectionController.availableCalendars.contains(where: \.isSuggestedByDefault)
            || systemCalendarConnectionController.hasSelectedCalendars
    }

    /// 四项配置检查全部通过后，允许把 checklist 收起。
    private var isCalendarConfigurationComplete: Bool {
        hasAddedCalDAVAccount
            && systemCalendarConnectionController.authorizationState == .authorized
            && systemCalendarConnectionController.hasSelectedCalendars
    }

    private var calendarConfigurationSummaryLine: String {
        if isCalendarConfigurationComplete {
            return localized("四项接入检查均已通过。需要时可展开查看完整步骤。", "All four setup checks have passed. Expand the list if you need to review the steps.")
        }

        return localized("沿用飞书 CalDAV -> macOS 日历 -> EventKit 的本地同步链路；只要还有未完成项，就继续保持展开。", "Uses the existing Feishu CalDAV -> macOS Calendar -> EventKit flow. The checklist stays open until every required item is complete.")
    }

    private var localizedCalendarSelectionSummary: String {
        let count = systemCalendarConnectionController.selectedCalendarIDs.count

        if count == 0 {
            return localized("尚未选择系统日历", "No calendar selected")
        }

        return localized("已选 \(count) 个日历", "\(count) calendar(s) selected")
    }

    /// `SourceCoordinator.lastRefreshLine` 仍保留中文兜底语义。
    /// 设置页切到英文时，这里改为直接消费原始时间并重新组装本地化展示，避免混入中文。
    private var localizedLastRefreshLine: String {
        guard let lastRefreshAt = sourceCoordinator.state.lastRefreshAt else {
            return localized("尚未刷新", "Not yet refreshed")
        }

        return Self.absoluteFormatter.string(from: lastRefreshAt)
    }

    private var localizedSyncFreshnessSummary: String {
        guard let lastRefreshAt = sourceCoordinator.state.lastRefreshAt else {
            return localized("尚未成功读取本地系统日历。", "The app has not successfully read the local Calendar database yet.")
        }

        let elapsed = Date().timeIntervalSince(lastRefreshAt)
        let elapsedDescription = localizedElapsedDescription(elapsed)

        if elapsed <= 10 * 60 {
            return localized("最近一次成功读取本地系统日历是在 \(elapsedDescription) 前。", "The local Calendar database was successfully read \(elapsedDescription) ago.")
        }

        return localized("距离最近一次成功读取本地系统日历已过去 \(elapsedDescription)。", "It has been \(elapsedDescription) since the last successful local Calendar read.")
    }

    private var localizedSyncFreshnessBadgeText: String {
        switch syncFreshnessStatus {
        case .idle:
            return localized("未检查", "Idle")
        case .pending:
            return localized("检查中", "Checking")
        case .passed:
            return localized("正常", "Fresh")
        case .warning:
            return localized("偏旧", "Stale")
        case .failed:
            return localized("失败", "Failed")
        }
    }

    private var localizedHealthStateSummary: String {
        switch sourceCoordinator.state.healthState {
        case .unconfigured:
            return localized("接入尚未完成，请先授权并选择目标日历。", "Setup is incomplete. Grant access and choose the calendars first.")
        case .ready:
            return localized("本地日历读取正常，正在等待下一场可提醒会议。", "The local calendar bridge is healthy and waiting for the next eligible meeting.")
        case .warning:
            return localized("本地日历同步仍可继续使用，但需要关注同步状态。", "The local calendar source is still usable, but its sync state needs attention.")
        case .failed:
            return sourceCoordinator.state.lastErrorMessage
                ?? localized("当前无法正常读取会议。", "The app cannot read meetings right now.")
        }
    }

    private var localizedReminderStateSummary: String {
        switch reminderEngine.state {
        case .idle:
            return localized("当前没有活动提醒", "No active reminder")
        case let .scheduled(context):
            return localized("已为《\(context.meeting.title)》安排提醒", "Reminder scheduled for “\(context.meeting.title)”")
        case let .playing(context, _):
            if context.triggeredImmediately {
                return localized("已为《\(context.meeting.title)》立即进入会前倒计时", "Immediate countdown started for “\(context.meeting.title)”")
            }

            return localized("正在为《\(context.meeting.title)》执行会前倒计时", "Countdown is running for “\(context.meeting.title)”")
        case let .triggeredSilently(context, _, reason):
            switch reason {
            case .userMuted:
                return localized("《\(context.meeting.title)》已静默提醒", "“\(context.meeting.title)” was triggered silently")
            case .outputRoutePolicy:
                return localized("《\(context.meeting.title)》因输出策略静默提醒", "“\(context.meeting.title)” was silenced by the output policy")
            }
        case .disabled:
            return localized("提醒已关闭", "Reminders are off")
        case .failed:
            return localized("提醒链路异常", "Reminder pipeline failed")
        }
    }

    private var localizedReminderStateDetailLine: String {
        switch reminderEngine.state {
        case .idle:
            return localized("当前没有活动提醒任务。", "There is no active reminder task right now.")
        case let .scheduled(context):
            return localized("将于 \(Self.absoluteFormatter.string(from: context.triggerAt)) 触发，倒计时 \(context.countdownSeconds) 秒。", "The reminder triggers at \(Self.absoluteFormatter.string(from: context.triggerAt)) with a \(context.countdownSeconds)-second countdown.")
        case let .playing(context, startedAt):
            if context.triggeredImmediately {
                return localized("距离会议已不足 \(context.countdownSeconds) 秒，因此在 \(Self.absoluteFormatter.string(from: startedAt)) 立即开始播放提醒。", "The meeting was already inside the \(context.countdownSeconds)-second window, so playback started immediately at \(Self.absoluteFormatter.string(from: startedAt)).")
            }

            return localized("已在 \(Self.absoluteFormatter.string(from: startedAt)) 开始执行会前倒计时并播放提醒音频。", "Playback started at \(Self.absoluteFormatter.string(from: startedAt)) and the pre-meeting countdown is now active.")
        case let .triggeredSilently(_, triggeredAt, reason):
            switch reason {
            case .userMuted:
                return localized("提醒已在 \(Self.absoluteFormatter.string(from: triggeredAt)) 命中，但当前是静音模式。", "The reminder triggered at \(Self.absoluteFormatter.string(from: triggeredAt)), but mute mode is enabled.")
            case .outputRoutePolicy(let routeName):
                return localized("提醒已在 \(Self.absoluteFormatter.string(from: triggeredAt)) 命中，但当前输出“\(routeName)”不满足仅耳机播放策略。", "The reminder triggered at \(Self.absoluteFormatter.string(from: triggeredAt)), but the current output “\(routeName)” does not satisfy the headphones-only policy.")
            }
        case .disabled:
            return localized("总提醒开关关闭后，不会创建新的本地提醒任务。", "No local reminder task is created while the global reminder switch is off.")
        case .failed:
            return sourceCoordinator.state.lastErrorMessage
                ?? localized("提醒引擎当前没有成功执行。", "The reminder engine is not operating correctly.")
        }
    }

    private var localizedLaunchAtLoginStatusSummary: String {
        launchAtLoginController.statusSummary(for: uiLanguage)
    }

    private func localizedAuthorizationSummary(for state: SystemCalendarAuthorizationState) -> String {
        switch state {
        case .authorized:
            return localized("系统日历权限已授权，可读取 Calendar 事件。", "Calendar access has been granted and events can be read.")
        case .notDetermined:
            return localized("系统还没有决定是否允许访问日历。", "Calendar access has not been decided yet.")
        case .denied:
            return localized("系统日历权限已被拒绝，请先在系统设置中允许访问。", "Calendar access was denied. Re-enable it in System Settings first.")
        case .restricted:
            return localized("系统日历权限受系统限制，当前无法读取。", "Calendar access is restricted by the system and cannot be read.")
        case .writeOnly:
            return localized("当前只有写入权限，无法读取已有事件。", "Only write access is available, so existing events cannot be read.")
        case .unknown:
            return localized("当前无法确认系统日历权限状态。", "The current Calendar permission state could not be determined.")
        }
    }

    private func localizedAuthorizationBadgeText(for state: SystemCalendarAuthorizationState) -> String {
        switch state {
        case .authorized:
            return localized("已授权", "Granted")
        case .notDetermined:
            return localized("待授权", "Pending")
        case .denied, .restricted, .writeOnly:
            return localized("不可读", "Blocked")
        case .unknown:
            return localized("未知", "Unknown")
        }
    }

    private func localizedCalendarSubtitle(for calendar: SystemCalendarDescriptor) -> String {
        let sourceTypeLabel = localizedCalendarSourceTypeLabel(calendar.sourceTypeLabel)

        if calendar.sourceTitle.isEmpty {
            return sourceTypeLabel
        }

        return "\(calendar.sourceTitle) · \(sourceTypeLabel)"
    }

    private func localizedCalendarSourceTypeLabel(_ label: String) -> String {
        switch label {
        case "本地":
            return localized("本地", "Local")
        case "订阅":
            return localized("订阅", "Subscribed")
        case "生日":
            return localized("生日", "Birthdays")
        case "其他":
            return localized("其他", "Other")
        default:
            return label
        }
    }

    private func localizedMeetingStartLine(for meeting: MeetingRecord) -> String {
        "\(Self.absoluteFormatter.string(from: meeting.startAt)) (\(localizedCountdownLine(until: meeting.startAt)))"
    }

    private func localizedCountdownLine(until date: Date) -> String {
        let interval = max(0, date.timeIntervalSinceNow)

        if interval < 60 {
            return localized("即将开始", "Starting Soon")
        }

        let totalSeconds = Int(interval.rounded(.up))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if uiLanguage == .english {
            if hours > 0 {
                return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
            }

            return "\(max(1, minutes))m"
        }

        if hours > 0 {
            return minutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes) 分钟"
        }

        return "\(max(1, minutes)) 分钟"
    }

    private func localizedElapsedDescription(_ elapsed: TimeInterval) -> String {
        let totalMinutes = max(1, Int(elapsed / 60))

        if uiLanguage == .english {
            guard totalMinutes >= 60 else {
                return totalMinutes == 1 ? "1 minute" : "\(totalMinutes) minutes"
            }

            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if minutes == 0 {
                return hours == 1 ? "1 hour" : "\(hours) hours"
            }

            return "\(hours)h \(minutes)m"
        }

        guard totalMinutes >= 60 else {
            return "\(totalMinutes) 分钟"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if minutes == 0 {
            return "\(hours) 小时"
        }

        return "\(hours) 小时 \(minutes) 分钟"
    }

    /// `SoundProfile.durationLine` 当前仍是中文格式。
    /// 这里在壳层重组一份跟随界面语言的时长文案，避免英文界面夹杂“秒 / 分钟”。
    private func localizedDurationLine(for duration: TimeInterval) -> String {
        let totalSeconds = max(1, Int(ceil(duration)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if uiLanguage == .english {
            if minutes == 0 {
                return "\(seconds)s"
            }

            if seconds == 0 {
                return "\(minutes)m"
            }

            return "\(minutes)m \(seconds)s"
        }

        if minutes == 0 {
            return "\(seconds) 秒"
        }

        if seconds == 0 {
            return "\(minutes) 分钟"
        }

        return "\(minutes) 分 \(seconds) 秒"
    }

    private func localizedJoinActionTitle(for meeting: MeetingRecord) -> String {
        localized(meeting.hasVideoConferenceLink ? "加入会议" : "打开事件", meeting.hasVideoConferenceLink ? "Join Video" : "Open Event")
    }

    private func responsiveCardColumns(minimum: CGFloat, maximum: CGFloat = 360) -> [GridItem] {
        [
            GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: 16, alignment: .topLeading)
        ]
    }

    private func localized(_ chinese: String, _ english: String) -> String {
        uiLanguage == .english ? english : chinese
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case overview
    case calendar
    case reminders
    case audio
    case advanced

    var id: String { rawValue }

    func title(for language: AppUILanguage) -> String {
        switch self {
        case .overview:
            return language == .english ? "Overview" : "概览"
        case .calendar:
            return language == .english ? "Calendar" : "日历"
        case .reminders:
            return language == .english ? "Reminders" : "提醒"
        case .audio:
            return language == .english ? "Audio" : "音频"
        case .advanced:
            return language == .english ? "Advanced" : "高级"
        }
    }
}

private extension AppUILanguage {
    /// 语言选项使用各自的原生名字，避免在不知道当前界面语言时找不到切换入口。
    var optionLabel: String {
        switch self {
        case .simplifiedChinese:
            return "中文"
        case .english:
            return "English"
        }
    }
}

/// 切换设置页 tab 时使用轻微下移 + 淡入，避免内容像整块硬切。
private struct SettingsPageTransitionModifier: ViewModifier {
    let opacity: Double
    let offsetY: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: offsetY)
    }
}

private extension AnyTransition {
    static var settingsPageSwap: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SettingsPageTransitionModifier(opacity: 0, offsetY: 8),
                identity: SettingsPageTransitionModifier(opacity: 1, offsetY: 0)
            ),
            removal: .opacity
        )
    }
}
