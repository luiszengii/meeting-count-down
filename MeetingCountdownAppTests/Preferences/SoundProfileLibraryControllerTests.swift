import Combine
@testable import FeishuMeetingCountdown
import Foundation
import XCTest

/// 这些测试锁定提醒音频列表控制器最核心的导入、切换和回退行为。
@MainActor
final class SoundProfileLibraryControllerTests: XCTestCase {
    /// 验证多次导入会把新音频追加到既有列表后面，而不是覆盖掉之前已上传的音频。
    func testImportSoundFilesAppendsToExistingLibrary() async {
        let bundledDefault = SoundProfile.bundledDefault(duration: 2)
        let existingImported = importedSoundProfile(id: "existing", fileName: "existing.wav", duration: 4)
        let importedA = importedSoundProfile(id: "import-a", fileName: "gong.wav", duration: 6)
        let importedB = importedSoundProfile(id: "import-b", fileName: "bell.mp3", duration: 9)
        let preferencesStore = InMemoryPreferencesStore(
            soundProfiles: [existingImported]
        )
        let assetStore = StubSoundProfileAssetStore(
            bundledDefault: bundledDefault,
            importBatch: SoundProfileImportBatch(
                importedProfiles: [importedA, importedB],
                failures: []
            )
        )
        let previewPlayer = StubSoundProfilePreviewPlayer()
        let controller = SoundProfileLibraryController(
            preferencesStore: preferencesStore,
            assetStore: assetStore,
            previewPlayer: previewPlayer,
            autoRefreshOnStart: false
        )

        await controller.refresh()
        await controller.importSoundFiles(
            from: [
                URL(fileURLWithPath: "/tmp/gong.wav"),
                URL(fileURLWithPath: "/tmp/bell.mp3")
            ]
        )
        let storedSoundProfiles = await preferencesStore.loadSoundProfiles()

        XCTAssertEqual(
            controller.soundProfiles.map(\.id),
            [bundledDefault.id, existingImported.id, importedA.id, importedB.id]
        )
        XCTAssertEqual(controller.selectedSoundProfileID, bundledDefault.id)
        XCTAssertEqual(storedSoundProfiles, [existingImported, importedA, importedB])
    }

    /// 验证删除当前正在使用的用户音频时，会自动回退到内建默认音频。
    func testDeleteCurrentImportedSoundFallsBackToBundledDefault() async {
        let bundledDefault = SoundProfile.bundledDefault(duration: 2)
        let imported = importedSoundProfile(id: "selected", fileName: "selected.wav", duration: 8)
        let preferencesStore = InMemoryPreferencesStore(
            soundProfiles: [imported],
            selectedSoundProfileID: imported.id
        )
        let assetStore = StubSoundProfileAssetStore(
            bundledDefault: bundledDefault,
            importBatch: SoundProfileImportBatch(importedProfiles: [], failures: [])
        )
        let controller = SoundProfileLibraryController(
            preferencesStore: preferencesStore,
            assetStore: assetStore,
            previewPlayer: StubSoundProfilePreviewPlayer(),
            autoRefreshOnStart: false
        )

        await controller.refresh()
        await controller.deleteSoundProfile(id: imported.id)
        let storedSelectedSoundProfileID = await preferencesStore.loadSelectedSoundProfileID()
        let deletedProfileIDs = await assetStore.loadDeletedProfileIDs()

        XCTAssertEqual(controller.selectedSoundProfileID, bundledDefault.id)
        XCTAssertEqual(controller.soundProfiles.map(\.id), [bundledDefault.id])
        XCTAssertEqual(storedSelectedSoundProfileID, bundledDefault.id)
        XCTAssertEqual(deletedProfileIDs, [imported.id])
    }

    /// 验证试听按钮会正确切换当前“播放 / 停止”状态。
    func testTogglePreviewTracksCurrentlyPreviewingSoundProfile() async {
        let bundledDefault = SoundProfile.bundledDefault(duration: 2)
        let imported = importedSoundProfile(id: "preview", fileName: "preview.wav", duration: 8)
        let controller = SoundProfileLibraryController(
            preferencesStore: InMemoryPreferencesStore(soundProfiles: [imported]),
            assetStore: StubSoundProfileAssetStore(
                bundledDefault: bundledDefault,
                importBatch: SoundProfileImportBatch(importedProfiles: [], failures: [])
            ),
            previewPlayer: StubSoundProfilePreviewPlayer(),
            autoRefreshOnStart: false
        )

        await controller.refresh()
        await controller.togglePreview(for: imported.id)

        XCTAssertEqual(controller.currentlyPreviewingSoundProfileID, imported.id)

        await controller.togglePreview(for: imported.id)

        XCTAssertNil(controller.currentlyPreviewingSoundProfileID)
    }

    /// 验证切换当前正式提醒音频后，会通过 `RefreshEventBus` 向总线发布 `.preferencesChanged` 事件。
    func testSelectSoundProfilePublishesPreferencesChangedEventOnBus() async {
        let bundledDefault = SoundProfile.bundledDefault(duration: 2)
        let imported = importedSoundProfile(id: "chosen", fileName: "chosen.wav", duration: 8)
        let bus = RefreshEventBus()
        var receivedTriggers: [RefreshTrigger] = []
        let cancellable = bus.publisher.sink { receivedTriggers.append($0) }

        let controller = SoundProfileLibraryController(
            preferencesStore: InMemoryPreferencesStore(soundProfiles: [imported]),
            assetStore: StubSoundProfileAssetStore(
                bundledDefault: bundledDefault,
                importBatch: SoundProfileImportBatch(importedProfiles: [], failures: [])
            ),
            previewPlayer: StubSoundProfilePreviewPlayer(),
            refreshEventBus: bus,
            autoRefreshOnStart: false
        )

        await controller.refresh()
        await controller.selectSoundProfile(id: imported.id)

        XCTAssertEqual(controller.selectedSoundProfileID, imported.id)
        XCTAssertEqual(receivedTriggers, [.preferencesChanged], "选择音频成功后应向总线发布 .preferencesChanged")
        _ = cancellable
    }

    /// 验证删除当前正在使用的音频后，会通过 `RefreshEventBus` 向总线发布 `.preferencesChanged` 事件。
    func testDeleteCurrentSoundProfilePublishesPreferencesChangedEventOnBus() async {
        let bundledDefault = SoundProfile.bundledDefault(duration: 2)
        let imported = importedSoundProfile(id: "selected", fileName: "selected.wav", duration: 8)
        let bus = RefreshEventBus()
        var receivedTriggers: [RefreshTrigger] = []
        let cancellable = bus.publisher.sink { receivedTriggers.append($0) }

        let controller = SoundProfileLibraryController(
            preferencesStore: InMemoryPreferencesStore(
                soundProfiles: [imported],
                selectedSoundProfileID: imported.id
            ),
            assetStore: StubSoundProfileAssetStore(
                bundledDefault: bundledDefault,
                importBatch: SoundProfileImportBatch(importedProfiles: [], failures: [])
            ),
            previewPlayer: StubSoundProfilePreviewPlayer(),
            refreshEventBus: bus,
            autoRefreshOnStart: false
        )

        await controller.refresh()
        await controller.deleteSoundProfile(id: imported.id)

        XCTAssertEqual(controller.selectedSoundProfileID, bundledDefault.id)
        XCTAssertEqual(receivedTriggers, [.preferencesChanged], "删除当前使用音频后应向总线发布 .preferencesChanged")
        _ = cancellable
    }

    /// 验证协议默认 `refresh()` 在调用过程中把 `loadingState` 拨到 `true`，
    /// 调用结束后归位 `false`，且正常完成时 `errorMessage` 为 `nil`。
    func testRefreshTogglesLoadingStateAndClearsErrorOnSuccess() async {
        let bundledDefault = SoundProfile.bundledDefault(duration: 2)
        let controller = SoundProfileLibraryController(
            preferencesStore: InMemoryPreferencesStore(),
            assetStore: StubSoundProfileAssetStore(
                bundledDefault: bundledDefault,
                importBatch: SoundProfileImportBatch(importedProfiles: [], failures: [])
            ),
            previewPlayer: StubSoundProfilePreviewPlayer(),
            autoRefreshOnStart: false
        )

        await controller.refresh()

        XCTAssertFalse(controller.loadingState, "loadingState 应在 refresh() 完成后归位 false")
        XCTAssertNil(controller.errorMessage, "正常完成时 errorMessage 应为 nil")
    }

    /// 构造一条用户上传音频，减少每个测试里重复写样板字段。
    private func importedSoundProfile(id: String, fileName: String, duration: TimeInterval) -> SoundProfile {
        SoundProfile(
            id: id,
            displayName: fileName,
            storage: .imported(fileName: fileName),
            duration: duration,
            createdAt: Date(timeIntervalSince1970: 1_234_567)
        )
    }
}

/// 用纯内存假资产存储替代真实文件系统，方便控制导入结果和删除记录。
actor StubSoundProfileAssetStore: SoundProfileAssetManaging {
    let bundledDefault: SoundProfile
    let importBatch: SoundProfileImportBatch
    private(set) var deletedProfileIDs: [String] = []

    init(bundledDefault: SoundProfile, importBatch: SoundProfileImportBatch) {
        self.bundledDefault = bundledDefault
        self.importBatch = importBatch
    }

    func bundledDefaultProfile() async -> SoundProfile {
        bundledDefault
    }

    func importSoundFiles(from urls: [URL]) async -> SoundProfileImportBatch {
        importBatch
    }

    func deleteImportedSoundProfile(_ profile: SoundProfile) async throws -> SoundProfileDeletionResult {
        deletedProfileIDs.append(profile.id)
        return .deleted
    }

    func url(for profile: SoundProfile) async throws -> URL {
        URL(fileURLWithPath: "/tmp/\(profile.id).wav")
    }

    func loadDeletedProfileIDs() async -> [String] {
        deletedProfileIDs
    }
}

/// 设置页试听并不需要真实音频输出；测试里只要记录按钮动作有没有被触发即可。
@MainActor
final class StubSoundProfilePreviewPlayer: SoundProfilePreviewPlaying {
    private(set) var playedProfileIDs: [String] = []
    private(set) var stopCallCount = 0

    func playPreview(of soundProfile: SoundProfile) async throws {
        playedProfileIDs.append(soundProfile.id)
    }

    func stopPreview() async {
        stopCallCount += 1
    }
}
