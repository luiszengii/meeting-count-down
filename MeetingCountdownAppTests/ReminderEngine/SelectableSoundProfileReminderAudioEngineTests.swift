import Foundation
import XCTest
@testable import FeishuMeetingCountdown

/// 这些测试锁定“当前选中提醒音频”接入正式提醒引擎后的关键时长选择规则。
@MainActor
final class SelectableSoundProfileReminderAudioEngineTests: XCTestCase {
    /// 验证如果当前选中的是用户上传音频，默认倒计时时长会跟随它的时长。
    func testDefaultSoundDurationUsesSelectedImportedSoundProfile() async throws {
        let imported = SoundProfile(
            id: "selected-imported",
            displayName: "gong.wav",
            storage: .imported(fileName: "gong.wav"),
            duration: 12,
            createdAt: Date(timeIntervalSince1970: 1_111)
        )
        let bundledDefault = SoundProfile.bundledDefault(duration: 2)
        let engine = SelectableSoundProfileReminderAudioEngine(
            preferencesStore: InMemoryPreferencesStore(
                soundProfiles: [imported],
                selectedSoundProfileID: imported.id
            ),
            assetStore: StubSelectableSoundProfileAssetStore(
                bundledDefault: bundledDefault
            )
        )

        let duration = try await engine.defaultSoundDuration()

        XCTAssertEqual(duration, imported.duration)
    }

    /// 验证如果当前选中的用户音频已经丢失，会保守回退到内建默认音频时长。
    func testDefaultSoundDurationFallsBackToBundledDefaultWhenSelectedImportedSoundIsMissing() async throws {
        let imported = SoundProfile(
            id: "missing-imported",
            displayName: "missing.wav",
            storage: .imported(fileName: "missing.wav"),
            duration: 12,
            createdAt: Date(timeIntervalSince1970: 1_111)
        )
        let bundledDefault = SoundProfile.bundledDefault(duration: 3)
        let assetStore = StubSelectableSoundProfileAssetStore(
            bundledDefault: bundledDefault,
            missingProfileIDs: [imported.id]
        )
        let engine = SelectableSoundProfileReminderAudioEngine(
            preferencesStore: InMemoryPreferencesStore(
                soundProfiles: [imported],
                selectedSoundProfileID: imported.id
            ),
            assetStore: assetStore
        )

        let duration = try await engine.defaultSoundDuration()

        XCTAssertEqual(duration, bundledDefault.duration)
    }
}

/// 给音频引擎测试提供可控的默认音频和“文件丢失”行为。
actor StubSelectableSoundProfileAssetStore: SoundProfileAssetManaging {
    let bundledDefault: SoundProfile
    let missingProfileIDs: Set<String>

    init(bundledDefault: SoundProfile, missingProfileIDs: Set<String> = []) {
        self.bundledDefault = bundledDefault
        self.missingProfileIDs = missingProfileIDs
    }

    func bundledDefaultProfile() async -> SoundProfile {
        bundledDefault
    }

    func importSoundFiles(from urls: [URL]) async -> SoundProfileImportBatch {
        SoundProfileImportBatch(importedProfiles: [], failures: [])
    }

    func deleteImportedSoundProfile(_ profile: SoundProfile) async throws {
        /// 这组测试不关心删除逻辑。
    }

    func url(for profile: SoundProfile) async throws -> URL {
        if missingProfileIDs.contains(profile.id) {
            throw SoundProfileAssetStoreError.missingImportedFile(fileName: profile.displayName)
        }

        return URL(fileURLWithPath: "/tmp/\(profile.id).wav")
    }
}
