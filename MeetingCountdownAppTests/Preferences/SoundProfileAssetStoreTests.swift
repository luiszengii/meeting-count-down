@testable import FeishuMeetingCountdown
import Foundation
import XCTest

/// 这些测试锁定 `SoundProfileAssetStore.deleteImportedSoundProfile(_:)` 的三种返回值语义。
final class SoundProfileAssetStoreTests: XCTestCase {
    /// 验证文件存在时删除成功，返回 `.deleted`。
    func testDeleteImportedSoundProfileReturnsDeletdWhenFileExists() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoundProfileAssetStoreTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let fileName = "\(UUID().uuidString).wav"
        let fileURL = tempDir.appendingPathComponent(fileName, isDirectory: false)
        try Data().write(to: fileURL)

        let store = SoundProfileAssetStore(
            fileManager: .default,
            bundle: .main,
            importedSoundsDirectoryURL: tempDir
        )

        let profile = SoundProfile(
            id: UUID().uuidString,
            displayName: fileName,
            storage: .imported(fileName: fileName),
            duration: 1,
            createdAt: Date()
        )

        let result = try await store.deleteImportedSoundProfile(profile)

        XCTAssertEqual(result, .deleted, "文件存在时应返回 .deleted")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fileURL.path),
            "删除成功后文件不应再存在"
        )
    }

    /// 验证文件不存在时删除为幂等空转，返回 `.alreadyMissing`。
    func testDeleteImportedSoundProfileReturnsAlreadyMissingWhenFileAbsent() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoundProfileAssetStoreTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let store = SoundProfileAssetStore(
            fileManager: .default,
            bundle: .main,
            importedSoundsDirectoryURL: tempDir
        )

        let profile = SoundProfile(
            id: UUID().uuidString,
            displayName: "nonexistent.wav",
            storage: .imported(fileName: "nonexistent.wav"),
            duration: 1,
            createdAt: Date()
        )

        let result = try await store.deleteImportedSoundProfile(profile)

        XCTAssertEqual(result, .alreadyMissing, "文件不存在时应返回 .alreadyMissing")
    }

    /// 验证 profile 的 storage 不是 `.imported` 类型时返回 `.staleMetadata`。
    func testDeleteImportedSoundProfileReturnsStaleMetadataForNonImportedProfile() async throws {
        let store = SoundProfileAssetStore(
            fileManager: .default,
            bundle: .main
        )

        let profile = SoundProfile.bundledDefault(duration: 1)

        let result = try await store.deleteImportedSoundProfile(profile)

        XCTAssertEqual(result, .staleMetadata, "非 imported storage 时应返回 .staleMetadata")
    }
}
