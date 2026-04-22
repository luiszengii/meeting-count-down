import Foundation

/// `SoundProfileLibraryController` 负责把"提醒音频列表"的读写、导入、删除和试听收口成设置页可消费的状态对象。
/// 视图层只负责触发动作，不直接处理文件复制、`UserDefaults` 持久化或试听播放器生命周期。
///
/// 遵从 `AsyncStateController`：
/// - `loadingState` 对应原 `isLoadingState`（首次读取或外部刷新列表时的忙碌标志）。
/// - `isImportingState` / `isApplyingState` 保留为独立属性（导入和应用时的忙碌标志），
///   语义上属于独立写入操作，不应合并进 `loadingState`。
/// - `errorMessage` 对应原 `lastErrorMessage`。
@MainActor
final class SoundProfileLibraryController: ObservableObject, AsyncStateController {
    /// 当前已经加载到内存里的完整音频列表，包含固定存在的内建默认音频。
    @Published private(set) var soundProfiles: [SoundProfile]
    /// 当前正式提醒真正使用的是哪一条音频。
    @Published private(set) var selectedSoundProfileID: String
    /// 首次读取或外部刷新列表时的加载状态。（AsyncStateController.loadingState）
    @Published var loadingState: Bool
    /// 批量导入用户音频时的忙碌状态。
    @Published private(set) var isImportingState: Bool
    /// 选择当前音频或删除现有音频时的忙碌状态。
    @Published private(set) var isApplyingState: Bool
    /// 当前正在试听的音频 ID；为 `nil` 表示当前没有试听中的项。
    @Published private(set) var currentlyPreviewingSoundProfileID: String?
    /// 最近一次需要展示给用户的错误。（AsyncStateController.errorMessage）
    @Published var errorMessage: String?

    /// 非敏感偏好持久化入口。
    private let preferencesStore: any PreferencesStore
    /// 负责真实音频文件复制、删除和 URL 解析的资产存储层。
    private let assetStore: any SoundProfileAssetManaging
    /// 设置页专用的试听播放器。
    private let previewPlayer: any SoundProfilePreviewPlaying
    /// 当前选中音频变化后，需要通知上游重算提醒。
    private let onSelectedSoundProfileChanged: @MainActor @Sendable () async -> Void

    /// 试听结束后自动把"播放中"按钮收回普通态的补偿任务。
    private var previewCompletionTask: Task<Void, Never>?

    init(
        preferencesStore: any PreferencesStore,
        assetStore: any SoundProfileAssetManaging,
        previewPlayer: any SoundProfilePreviewPlaying,
        onSelectedSoundProfileChanged: @escaping @MainActor @Sendable () async -> Void = {},
        autoRefreshOnStart: Bool = true
    ) {
        let bundledDefault = SoundProfile.bundledDefault(duration: 1)

        self.preferencesStore = preferencesStore
        self.assetStore = assetStore
        self.previewPlayer = previewPlayer
        self.onSelectedSoundProfileChanged = onSelectedSoundProfileChanged
        self.soundProfiles = [bundledDefault]
        self.selectedSoundProfileID = bundledDefault.id
        self.loadingState = false
        self.isImportingState = false
        self.isApplyingState = false
        self.currentlyPreviewingSoundProfileID = nil
        self.errorMessage = nil

        if autoRefreshOnStart {
            Task { [weak self] in
                await self?.refresh()
            }
        }
    }

    /// 当前正式提醒正在使用的音频条目，供设置页展示"当前使用中"状态。
    var selectedSoundProfile: SoundProfile? {
        soundProfiles.first(where: { $0.id == selectedSoundProfileID })
    }

    /// 从真实存储重建音频列表和当前选择（`AsyncStateController.performRefresh` 的实现）。
    func performRefresh() async throws {
        let hydratedState = await loadHydratedState()
        applyHydratedState(hydratedState)

        if hydratedState.storedSelectedSoundProfileID != hydratedState.selectedSoundProfileID {
            try? await preferencesStore.saveSelectedSoundProfileID(hydratedState.selectedSoundProfileID)
        }
    }

    /// 批量导入用户选择的音频文件。
    func importSoundFiles(from urls: [URL]) async {
        guard !urls.isEmpty else {
            return
        }

        isImportingState = true
        errorMessage = nil

        defer {
            isImportingState = false
        }

        let importBatch = await assetStore.importSoundFiles(from: urls)

        if !importBatch.importedProfiles.isEmpty {
            let updatedImportedProfiles = soundProfiles.filter(\.isImported) + importBatch.importedProfiles

            do {
                try await preferencesStore.saveSoundProfiles(updatedImportedProfiles)
                applyHydratedState(await loadHydratedState())
            } catch {
                for soundProfile in importBatch.importedProfiles {
                    try? await assetStore.deleteImportedSoundProfile(soundProfile)
                }

                errorMessage = error.localizedDescription
                return
            }
        }

        if !importBatch.failures.isEmpty {
            errorMessage = importBatch.failures
                .map { "\($0.fileName)：\($0.message)" }
                .joined(separator: "\n")
        }
    }

    /// 把某条音频设为正式提醒当前使用的音频。
    func selectSoundProfile(id: String) async {
        guard soundProfiles.contains(where: { $0.id == id }) else {
            return
        }

        guard selectedSoundProfileID != id else {
            return
        }

        isApplyingState = true
        errorMessage = nil

        defer {
            isApplyingState = false
        }

        do {
            try await preferencesStore.saveSelectedSoundProfileID(id)
            selectedSoundProfileID = id
            await onSelectedSoundProfileChanged()
        } catch {
            errorMessage = error.localizedDescription
            applyHydratedState(await loadHydratedState())
        }
    }

    /// 删除一条用户上传的音频；如果它正被正式提醒使用，则自动回退到内建默认音频。
    func deleteSoundProfile(id: String) async {
        guard let soundProfile = soundProfiles.first(where: { $0.id == id }), soundProfile.isImported else {
            return
        }

        isApplyingState = true
        errorMessage = nil

        let selectionChanged = selectedSoundProfileID == id
        let fallbackSelectedID = selectionChanged ? SoundProfile.bundledDefaultID : selectedSoundProfileID

        defer {
            isApplyingState = false
        }

        if currentlyPreviewingSoundProfileID == id {
            await stopPreview()
        }

        do {
            let remainingImportedProfiles = soundProfiles
                .filter(\.isImported)
                .filter { $0.id != id }

            try await preferencesStore.saveSoundProfiles(remainingImportedProfiles)
            try await preferencesStore.saveSelectedSoundProfileID(fallbackSelectedID)

            do {
                try await assetStore.deleteImportedSoundProfile(soundProfile)
            } catch {
                errorMessage = error.localizedDescription
            }

            applyHydratedState(await loadHydratedState())

            if selectionChanged {
                await onSelectedSoundProfileChanged()
            }
        } catch {
            errorMessage = error.localizedDescription
            applyHydratedState(await loadHydratedState())
        }
    }

    /// 同一按钮既负责开始试听，也负责停止当前试听。
    func togglePreview(for id: String) async {
        guard let soundProfile = soundProfiles.first(where: { $0.id == id }) else {
            return
        }

        if currentlyPreviewingSoundProfileID == id {
            await stopPreview()
            return
        }

        errorMessage = nil
        await stopPreview()

        do {
            try await previewPlayer.playPreview(of: soundProfile)
            currentlyPreviewingSoundProfileID = id
            schedulePreviewCompletion(for: soundProfile)
        } catch {
            errorMessage = error.localizedDescription
            currentlyPreviewingSoundProfileID = nil
        }
    }

    /// 让设置页在文件选择器直接报错时，也能把错误展示到统一位置。
    func reportFileImportFailure(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    /// 主动停止当前试听中的音频。
    func stopPreview() async {
        previewCompletionTask?.cancel()
        previewCompletionTask = nil
        currentlyPreviewingSoundProfileID = nil
        await previewPlayer.stopPreview()
    }

    /// 把存储层里的用户音频和内建默认音频合并成设置页真正需要的状态快照。
    private func loadHydratedState() async -> HydratedSoundProfileState {
        let bundledDefault = await assetStore.bundledDefaultProfile()
        let storedProfiles = await preferencesStore.loadSoundProfiles()
        let hydratedProfiles = SoundProfile.mergedWithBundledDefault(
            storedProfiles,
            bundledDefault: bundledDefault
        )
        let storedSelectedSoundProfileID = await preferencesStore.loadSelectedSoundProfileID()
        let selectedSoundProfileID =
            storedSelectedSoundProfileID.flatMap { storedID in
                hydratedProfiles.contains(where: { $0.id == storedID }) ? storedID : nil
            }
            ?? bundledDefault.id

        return HydratedSoundProfileState(
            soundProfiles: hydratedProfiles,
            selectedSoundProfileID: selectedSoundProfileID,
            storedSelectedSoundProfileID: storedSelectedSoundProfileID
        )
    }

    /// 把计算好的快照应用到 `@Published` 状态上，并处理试听状态的回收。
    private func applyHydratedState(_ state: HydratedSoundProfileState) {
        soundProfiles = state.soundProfiles
        selectedSoundProfileID = state.selectedSoundProfileID

        if let previewingID = currentlyPreviewingSoundProfileID,
           !state.soundProfiles.contains(where: { $0.id == previewingID }) {
            previewCompletionTask?.cancel()
            previewCompletionTask = nil
            currentlyPreviewingSoundProfileID = nil
        }
    }

    /// 试听播放完之后，把行内按钮状态自动收回"播放"。
    private func schedulePreviewCompletion(for soundProfile: SoundProfile) {
        previewCompletionTask?.cancel()

        previewCompletionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(1, soundProfile.duration)))
            } catch {
                return
            }

            await self?.finishPreviewIfNeeded(for: soundProfile.id)
        }
    }

    /// 只有当前试听状态仍然对应同一条音频时，才允许自动收回"播放中"状态。
    private func finishPreviewIfNeeded(for soundProfileID: String) async {
        guard currentlyPreviewingSoundProfileID == soundProfileID else {
            return
        }

        previewCompletionTask = nil
        currentlyPreviewingSoundProfileID = nil
    }
}

/// `HydratedSoundProfileState` 把设置页真正需要的音频列表状态打包成纯值。
/// 这样控制器里的"加载"和"应用"职责就能保持清晰，不把一堆中间量散落在多个方法之间。
private struct HydratedSoundProfileState {
    /// 含内建默认音频的完整列表。
    let soundProfiles: [SoundProfile]
    /// 当前正式提醒使用的音频 ID。
    let selectedSoundProfileID: String
    /// 持久化层原本保存的选中音频 ID，用于判断是否需要回写修复。
    let storedSelectedSoundProfileID: String?
}
