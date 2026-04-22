import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// `SettingsView` 现在只负责设置窗口壳层：注入依赖、切换 tab、
/// 维护页面注册表，以及管理首次展开状态和音频文件导入。
/// 具体 tab 页面已拆到各自独立的 View struct（实现 SettingsPage 协议），
/// 这样后续维护不必再回到单一大文件。
///
/// 详见 ADR: docs/adrs/2026-04-22-settings-page-registry.md
struct SettingsView: View {
    @ObservedObject var sourceCoordinator: SourceCoordinator
    @ObservedObject var systemCalendarConnectionController: SystemCalendarConnectionController
    @ObservedObject var reminderEngine: ReminderEngine
    @ObservedObject var reminderPreferencesController: ReminderPreferencesController
    @ObservedObject var soundProfileLibraryController: SoundProfileLibraryController
    @ObservedObject var launchAtLoginController: LaunchAtLoginController

    @State var isPresentingSoundImporter = false
    @State var selectedTab: SettingsTab = .overview

    /// 页面注册表：每次 body 重绘时按顺序构建，保持与 SettingsTab 枚举顺序一致。
    /// SettingsPage 协议使用 `any SettingsPage` 存在性，不需要关联类型，
    /// 因此可以直接存入同构数组。
    var pages: [any SettingsPage] {
        [
            OverviewPage(
                sourceCoordinator: sourceCoordinator,
                systemCalendarConnectionController: systemCalendarConnectionController,
                reminderEngine: reminderEngine,
                reminderPreferencesController: reminderPreferencesController,
                soundProfileLibraryController: soundProfileLibraryController,
                onNavigate: { tab in selectedTab = tab }
            ),
            CalendarPage(
                systemCalendarConnectionController: systemCalendarConnectionController,
                sourceCoordinator: sourceCoordinator
            ),
            RemindersPage(
                reminderEngine: reminderEngine,
                reminderPreferencesController: reminderPreferencesController,
                soundProfileLibraryController: soundProfileLibraryController
            ),
            AudioPage(
                soundProfileLibraryController: soundProfileLibraryController,
                reminderPreferencesController: reminderPreferencesController,
                isPresentingSoundImporter: $isPresentingSoundImporter
            ),
            AdvancedPage(
                sourceCoordinator: sourceCoordinator,
                systemCalendarConnectionController: systemCalendarConnectionController,
                reminderPreferencesController: reminderPreferencesController,
                launchAtLoginController: launchAtLoginController
            )
        ]
    }

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
                .frame(maxWidth: 1_040, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}
