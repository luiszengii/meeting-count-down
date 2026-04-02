import AVFoundation
import Foundation

/// `SelectableSoundProfileReminderAudioEngine` 让正式提醒音频不再固定绑定到单个 bundle 资源。
/// 它会根据当前选中的 `SoundProfile` 播放真正的提醒音频，并在用户音频不可用时保守回退到内建默认音频。
@MainActor
final class SelectableSoundProfileReminderAudioEngine: ReminderAudioEngine {
    /// 读取当前选中提醒音频所需的持久化入口。
    private let preferencesStore: any PreferencesStore
    /// 负责把 `SoundProfile` 解析成真实文件，并提供内建默认音频元数据。
    private let assetStore: any SoundProfileAssetManaging
    /// 当当前音频和内建默认音频都不可用时的最后兜底。
    private let fallbackEngine: (any ReminderAudioEngine)?
    /// 当前已经加载好的播放器；只要选中音频没变，就可以直接复用。
    private var player: AVAudioPlayer?
    /// 记录缓存播放器对应的是哪一条音频，避免选中项变化后还继续复用旧播放器。
    private var loadedSoundProfileID: String?

    init(
        preferencesStore: any PreferencesStore,
        assetStore: any SoundProfileAssetManaging,
        fallbackEngine: (any ReminderAudioEngine)? = nil
    ) {
        self.preferencesStore = preferencesStore
        self.assetStore = assetStore
        self.fallbackEngine = fallbackEngine
    }

    /// 预热当前选中音频的播放器，尽量降低第一次提醒时的解码延迟。
    func warmUp() async throws {
        do {
            let selection = try await resolvePlayableSelection()
            let player = try loadPlayer(for: selection)
            player.prepareToPlay()
        } catch {
            if let fallbackEngine {
                try await fallbackEngine.warmUp()
                return
            }

            throw error
        }
    }

    /// 默认倒计时时长跟随当前选中的提醒音频。
    func defaultSoundDuration() async throws -> TimeInterval {
        do {
            return try await resolvePlayableSelection().soundProfile.duration
        } catch {
            if let fallbackEngine {
                return try await fallbackEngine.defaultSoundDuration()
            }

            throw error
        }
    }

    /// 正式提醒总是从头播放当前选中的音频。
    func playDefaultSound() async throws {
        do {
            let selection = try await resolvePlayableSelection()
            let player = try loadPlayer(for: selection)
            player.stop()
            player.currentTime = 0
            player.prepareToPlay()

            guard player.play() else {
                throw ReminderAudioEngineError.failedToStartPlayback(url: selection.url)
            }
        } catch {
            if let fallbackEngine {
                try await fallbackEngine.playDefaultSound()
                return
            }

            throw error
        }
    }

    /// 停止当前正式提醒音频；兜底播放器也一并停止，避免旧播放残留。
    func stopPlayback() async {
        player?.stop()

        if let fallbackEngine {
            await fallbackEngine.stopPlayback()
        }
    }

    /// 解析当前真正可播放的音频。
    /// 如果选中的用户音频文件已经丢失，会自动回退到内建默认音频。
    private func resolvePlayableSelection() async throws -> ResolvedSoundProfileSelection {
        let bundledDefault = await assetStore.bundledDefaultProfile()
        let storedProfiles = await preferencesStore.loadSoundProfiles()
        let availableProfiles = SoundProfile.mergedWithBundledDefault(
            storedProfiles,
            bundledDefault: bundledDefault
        )
        let storedSelectedSoundProfileID = await preferencesStore.loadSelectedSoundProfileID()
        let preferredSoundProfile =
            storedSelectedSoundProfileID.flatMap { selectedID in
                availableProfiles.first(where: { $0.id == selectedID })
            }
            ?? bundledDefault

        do {
            let url = try await assetStore.url(for: preferredSoundProfile)
            return ResolvedSoundProfileSelection(soundProfile: preferredSoundProfile, url: url)
        } catch {
            guard preferredSoundProfile.id != bundledDefault.id else {
                throw error
            }

            let bundledURL = try await assetStore.url(for: bundledDefault)
            return ResolvedSoundProfileSelection(soundProfile: bundledDefault, url: bundledURL)
        }
    }

    /// 惰性加载并缓存当前选中音频对应的播放器。
    private func loadPlayer(for selection: ResolvedSoundProfileSelection) throws -> AVAudioPlayer {
        if loadedSoundProfileID == selection.soundProfile.id, let player {
            return player
        }

        do {
            let player = try AVAudioPlayer(contentsOf: selection.url)
            player.volume = 1.0
            player.prepareToPlay()
            self.player = player
            self.loadedSoundProfileID = selection.soundProfile.id
            return player
        } catch {
            throw ReminderAudioEngineError.failedToLoadBundledResource(
                url: selection.url,
                underlyingError: error
            )
        }
    }
}

/// `ResolvedSoundProfileSelection` 把“音频条目”与“它对应的真实文件 URL”打包到一起。
/// 这样播放器缓存和回退逻辑就不需要在多个方法里反复拆分同一组数据。
private struct ResolvedSoundProfileSelection {
    /// 当前真正会被播放或用于倒计时的音频条目。
    let soundProfile: SoundProfile
    /// 这条音频对应的真实文件 URL。
    let url: URL
}
