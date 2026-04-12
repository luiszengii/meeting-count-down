import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// `SettingsView` 现在只负责设置窗口壳层：注入依赖、切换 tab、
/// 管理首次展开状态和音频文件导入。具体 tab 页面与共享设置组件
/// 已拆到 `AppShell/Settings/`，这样后续维护不必再回到一个近两千行的大文件。
struct SettingsView: View {
    @ObservedObject var sourceCoordinator: SourceCoordinator
    @ObservedObject var systemCalendarConnectionController: SystemCalendarConnectionController
    @ObservedObject var reminderEngine: ReminderEngine
    @ObservedObject var reminderPreferencesController: ReminderPreferencesController
    @ObservedObject var soundProfileLibraryController: SoundProfileLibraryController
    @ObservedObject var launchAtLoginController: LaunchAtLoginController

    @State var isPresentingSoundImporter = false
    @State var selectedTab: SettingsTab = .overview
    @State var isCalendarConfigurationExpanded = true
    @State var hasInitializedCalendarConfigurationExpansion = false
    @State var hoveredSoundProfileID: SoundProfile.ID?
    @State var didCopyCalendarDiagnostics = false

    var body: some View {
        ZStack {
            GlassBackdrop()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    tabBar
                    tabContent
                }
                .frame(maxWidth: 1_180, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity, alignment: .top)
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
}
