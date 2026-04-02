import AVFoundation
import Foundation

/// `SoundProfileImportFailure` 记录一次批量导入里单个文件失败的结果。
/// 这样设置页就能告诉用户“哪几个文件成功了，哪几个没进列表”，而不是整批直接失败。
struct SoundProfileImportFailure: Equatable, Sendable {
    /// 失败文件的人类可读名称。
    let fileName: String
    /// 这次失败需要展示给用户的原因。
    let message: String
}

/// `SoundProfileImportBatch` 收口一次多文件导入的整体结果。
/// 导入支持部分成功，所以这里同时返回成功项和失败项。
struct SoundProfileImportBatch: Equatable, Sendable {
    /// 本次成功导入并已经拿到元数据的音频列表。
    let importedProfiles: [SoundProfile]
    /// 本次失败的文件与错误说明。
    let failures: [SoundProfileImportFailure]
}

/// `SoundProfileAssetManaging` 抽象提醒音频的真实文件管理能力。
/// 上层控制器只关心“导入结果是什么”“怎么删”“怎么重新定位到文件”，不关心目录结构细节。
protocol SoundProfileAssetManaging: Sendable {
    /// 返回当前 app 固定存在的内建默认提醒音频条目。
    func bundledDefaultProfile() async -> SoundProfile
    /// 把用户选择的多个音频文件复制进 app 自己管理的目录，并返回导入结果。
    func importSoundFiles(from urls: [URL]) async -> SoundProfileImportBatch
    /// 删除一条已经导入到 app 本地目录的音频文件。
    func deleteImportedSoundProfile(_ profile: SoundProfile) async throws
    /// 把一条音频条目重新解析成真实文件 URL。
    func url(for profile: SoundProfile) async throws -> URL
}

/// `SoundProfileAssetStoreError` 收拢本地音频文件管理层真正需要暴露给上游的错误。
/// 这样设置页和提醒引擎看到的都是“导入失败”“文件丢失”这类产品语义，而不是零散的文件系统报错。
enum SoundProfileAssetStoreError: LocalizedError {
    /// app bundle 中找不到内建默认提醒音频。
    case missingBundledResource(name: String, fileExtension: String)
    /// 用户导入的本地音频文件已经不存在。
    case missingImportedFile(fileName: String)
    /// 复制用户选择的音频文件到本地管理目录时失败。
    case failedToCopyImportedFile(fileName: String, underlyingError: Error)
    /// 文件虽然复制成功，但 `AVFoundation` 无法把它当成可播放音频。
    case unsupportedAudioFile(fileName: String, underlyingError: Error)
    /// 删除已导入音频文件时失败。
    case failedToDeleteImportedFile(fileName: String, underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case let .missingBundledResource(name, fileExtension):
            return "找不到内建提醒音频：\(name).\(fileExtension)"
        case let .missingImportedFile(fileName):
            return "已上传音频不存在：\(fileName)"
        case let .failedToCopyImportedFile(fileName, underlyingError):
            return "导入音频失败：\(fileName)，\(underlyingError.localizedDescription)"
        case let .unsupportedAudioFile(fileName, underlyingError):
            return "无法读取音频文件：\(fileName)，\(underlyingError.localizedDescription)"
        case let .failedToDeleteImportedFile(fileName, underlyingError):
            return "删除音频失败：\(fileName)，\(underlyingError.localizedDescription)"
        }
    }
}

/// `SoundProfileAssetStore` 负责管理提醒音频的真实文件。
/// 它把用户上传的音频统一复制到 app 自己管理的目录里，避免正式提醒依赖原始文件还留在桌面或下载目录。
actor SoundProfileAssetStore: SoundProfileAssetManaging {
    /// 底层文件系统入口。
    private let fileManager: FileManager
    /// 读取内建默认提醒音频时依赖的 bundle。
    private let bundle: Bundle
    /// 用户导入音频文件最终落地的目录。
    private let importedSoundsDirectoryURL: URL
    /// 如果默认音频资源意外缺失，就用这个兜底时长保证 UI 和倒计时不至于出现零值。
    private let fallbackBundledDuration: TimeInterval

    init(
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        importedSoundsDirectoryURL: URL? = nil,
        fallbackBundledDuration: TimeInterval = 1
    ) {
        self.fileManager = fileManager
        self.bundle = bundle
        self.importedSoundsDirectoryURL = importedSoundsDirectoryURL ?? Self.defaultImportedSoundsDirectory(
            fileManager: fileManager
        )
        self.fallbackBundledDuration = fallbackBundledDuration
    }

    /// 返回当前内建默认提醒音频，并尽量带上真实时长。
    func bundledDefaultProfile() async -> SoundProfile {
        let duration = (try? durationForAudioFile(at: try resolveBundledDefaultURL())) ?? fallbackBundledDuration
        return SoundProfile.bundledDefault(duration: duration)
    }

    /// 批量导入用户选择的音频文件；单个文件失败不会让整批全部作废。
    func importSoundFiles(from urls: [URL]) async -> SoundProfileImportBatch {
        var importedProfiles: [SoundProfile] = []
        var failures: [SoundProfileImportFailure] = []

        for url in urls {
            do {
                importedProfiles.append(try importSoundFile(from: url))
            } catch {
                failures.append(
                    SoundProfileImportFailure(
                        fileName: url.lastPathComponent,
                        message: error.localizedDescription
                    )
                )
            }
        }

        return SoundProfileImportBatch(importedProfiles: importedProfiles, failures: failures)
    }

    /// 删除一条已经导入到 app 本地目录的音频文件。
    func deleteImportedSoundProfile(_ profile: SoundProfile) async throws {
        guard case let .imported(fileName) = profile.storage else {
            return
        }

        let fileURL = importedSoundsDirectoryURL.appendingPathComponent(fileName, isDirectory: false)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            throw SoundProfileAssetStoreError.failedToDeleteImportedFile(
                fileName: fileName,
                underlyingError: error
            )
        }
    }

    /// 统一把音频条目解析成真实文件 URL。
    func url(for profile: SoundProfile) async throws -> URL {
        switch profile.storage {
        case let .bundled(resourceName, resourceExtension):
            guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
                throw SoundProfileAssetStoreError.missingBundledResource(
                    name: resourceName,
                    fileExtension: resourceExtension
                )
            }

            return url

        case let .imported(fileName):
            let fileURL = importedSoundsDirectoryURL.appendingPathComponent(fileName, isDirectory: false)

            guard fileManager.fileExists(atPath: fileURL.path) else {
                throw SoundProfileAssetStoreError.missingImportedFile(fileName: fileName)
            }

            return fileURL
        }
    }

    /// 导入单个音频文件时，先复制，再用真实落地文件做一次解码验证。
    private func importSoundFile(from sourceURL: URL) throws -> SoundProfile {
        let startedAccessing = sourceURL.startAccessingSecurityScopedResource()

        defer {
            if startedAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try ensureImportedSoundsDirectory()

        let profileID = UUID().uuidString
        let pathExtension = sourceURL.pathExtension
        let importedFileName: String

        if pathExtension.isEmpty {
            importedFileName = profileID
        } else {
            importedFileName = "\(profileID).\(pathExtension.lowercased())"
        }

        let destinationURL = importedSoundsDirectoryURL.appendingPathComponent(importedFileName, isDirectory: false)

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw SoundProfileAssetStoreError.failedToCopyImportedFile(
                fileName: sourceURL.lastPathComponent,
                underlyingError: error
            )
        }

        do {
            let duration = try durationForAudioFile(at: destinationURL)
            return SoundProfile(
                id: profileID,
                displayName: sourceURL.lastPathComponent,
                storage: .imported(fileName: importedFileName),
                duration: duration,
                createdAt: Date()
            )
        } catch {
            try? fileManager.removeItem(at: destinationURL)

            throw SoundProfileAssetStoreError.unsupportedAudioFile(
                fileName: sourceURL.lastPathComponent,
                underlyingError: error
            )
        }
    }

    /// 保证导入目录存在；如果目录还没创建，就先补出来。
    private func ensureImportedSoundsDirectory() throws {
        var isDirectory = ObjCBool(false)

        if fileManager.fileExists(atPath: importedSoundsDirectoryURL.path, isDirectory: &isDirectory) {
            return
        }

        try fileManager.createDirectory(
            at: importedSoundsDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    /// 用 `AVAudioPlayer` 校验文件确实可读，并拿到真实时长。
    private func durationForAudioFile(at url: URL) throws -> TimeInterval {
        let player = try AVAudioPlayer(contentsOf: url)
        return max(1, player.duration)
    }

    /// 读取 bundle 里的内建默认提醒音频 URL。
    private func resolveBundledDefaultURL() throws -> URL {
        guard let url = bundle.url(
            forResource: SoundProfile.bundledDefaultResourceName,
            withExtension: SoundProfile.bundledDefaultResourceExtension
        ) else {
            throw SoundProfileAssetStoreError.missingBundledResource(
                name: SoundProfile.bundledDefaultResourceName,
                fileExtension: SoundProfile.bundledDefaultResourceExtension
            )
        }

        return url
    }

    /// 统一计算用户导入音频的落地目录，避免路径规则散落在控制器里。
    private nonisolated static func defaultImportedSoundsDirectory(fileManager: FileManager) -> URL {
        let applicationSupportURL =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory

        return applicationSupportURL
            .appendingPathComponent("FeishuMeetingCountdown", isDirectory: true)
            .appendingPathComponent("ReminderSounds", isDirectory: true)
    }
}
