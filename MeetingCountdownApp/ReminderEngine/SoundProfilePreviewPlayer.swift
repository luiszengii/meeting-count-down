import AVFoundation
import Foundation

/// `SoundProfilePreviewPlaying` 抽象设置页试听音频所需的最小播放能力。
/// 这样音频列表控制器只关心“能不能播”“要不要停”，不直接接触 `AVAudioPlayer`。
@MainActor
protocol SoundProfilePreviewPlaying: AnyObject {
    /// 试听一条指定的提醒音频。
    func playPreview(of soundProfile: SoundProfile) async throws
    /// 停止当前试听中的音频。
    func stopPreview() async
}

/// `SoundProfilePreviewPlayerError` 收口试听播放器真正需要暴露给设置页的错误。
enum SoundProfilePreviewPlayerError: LocalizedError {
    /// 已经拿到播放器，但开始播放失败。
    case failedToStartPlayback(fileName: String)

    var errorDescription: String? {
        switch self {
        case let .failedToStartPlayback(fileName):
            return "试听未能开始播放：\(fileName)"
        }
    }
}

/// `SoundProfilePreviewPlayer` 专门服务于设置页里的“播放 / 停止”试听按钮。
/// 它和正式提醒引擎使用不同的播放器实例，避免用户试听时把活动提醒状态机打乱。
@MainActor
final class SoundProfilePreviewPlayer: SoundProfilePreviewPlaying {
    /// 负责把音频条目重新解析成真实文件 URL。
    private let assetStore: any SoundProfileAssetManaging
    /// 当前试听播放器；需要长期持有，否则播放会被提前释放。
    private var player: AVAudioPlayer?

    init(assetStore: any SoundProfileAssetManaging) {
        self.assetStore = assetStore
    }

    /// 从头试听一条指定音频。
    func playPreview(of soundProfile: SoundProfile) async throws {
        let previewURL = try await assetStore.url(for: soundProfile)
        player?.stop()

        let player = try AVAudioPlayer(contentsOf: previewURL)
        player.volume = 1.0
        player.currentTime = 0
        player.prepareToPlay()

        guard player.play() else {
            throw SoundProfilePreviewPlayerError.failedToStartPlayback(fileName: soundProfile.displayName)
        }

        self.player = player
    }

    /// 停止当前试听播放。
    func stopPreview() async {
        player?.stop()
        player = nil
    }
}
