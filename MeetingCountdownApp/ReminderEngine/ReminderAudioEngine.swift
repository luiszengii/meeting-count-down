import AVFoundation
import Foundation

/// `ReminderAudioEngine` 把提醒引擎需要的最小音频能力抽象出来。
/// 提醒层只关心“默认音效多长”“能不能播放”“需要时停止播放”，不直接接触底层音频图。
@MainActor
protocol ReminderAudioEngine: AnyObject {
    /// 预热默认音频链路，尽量降低首次播放时的解码与启动延迟。
    func warmUp() async throws
    /// 返回当前默认音效的时长，供提醒引擎决定倒计时秒数。
    func defaultSoundDuration() async throws -> TimeInterval
    /// 播放内建默认音效。
    func playDefaultSound() async throws
    /// 停止当前播放中的默认音效。
    func stopPlayback() async
}

/// `ReminderAudioEngineError` 收拢默认音效资源加载失败时需要暴露给上层的错误。
/// 这样设置页或日志里就不会只看到模糊的底层 AVFoundation 报错。
enum ReminderAudioEngineError: LocalizedError {
    /// app bundle 里找不到配置的默认音效文件。
    case missingBundledResource(name: String, fileExtension: String)
    /// 资源文件存在，但无法被 `AVAudioPlayer` 初始化或开始播放。
    case failedToLoadBundledResource(url: URL, underlyingError: Error)
    /// 已经拿到播放器，但开始播放时失败。
    case failedToStartPlayback(url: URL)

    var errorDescription: String? {
        switch self {
        case let .missingBundledResource(name, fileExtension):
            return "找不到默认提醒音效资源：\(name).\(fileExtension)"
        case let .failedToLoadBundledResource(url, underlyingError):
            return "加载默认提醒音效失败：\(url.lastPathComponent)，\(underlyingError.localizedDescription)"
        case let .failedToStartPlayback(url):
            return "默认提醒音效未能开始播放：\(url.lastPathComponent)"
        }
    }
}

/// `BundledAudioFileReminderAudioEngine` 优先播放 app bundle 内的真实音频文件。
/// 这比程序生成短音更贴近用户最终体验，也更适合排查“提醒到了但完全听不见”的问题。
@MainActor
final class BundledAudioFileReminderAudioEngine: ReminderAudioEngine {
    /// 资源文件名，不含扩展名。
    private let resourceName: String
    /// 资源扩展名。
    private let resourceExtension: String
    /// 默认从主 bundle 读取资源，便于直接随 app 一起分发。
    private let bundle: Bundle
    /// 当资源缺失或系统解码失败时，退回到旧的生成短音实现，避免提醒链路完全失效。
    private let fallbackEngine: (any ReminderAudioEngine)?
    /// 真正负责文件播放的播放器；需要长期持有，否则播放会被提前释放。
    private var player: AVAudioPlayer?
    /// 缓存已经解析出的资源 URL，避免每次播放都重新走 bundle 查找。
    private var cachedResourceURL: URL?
    /// 统一的运维日志通道，主要用于记录降级到兜底引擎的情况。
    private let logger = AppLogger(source: "ReminderAudioEngine.BundledAudioFile")

    init(
        resourceName: String,
        resourceExtension: String,
        bundle: Bundle = .main,
        fallbackEngine: (any ReminderAudioEngine)? = nil
    ) {
        self.resourceName = resourceName
        self.resourceExtension = resourceExtension
        self.bundle = bundle
        self.fallbackEngine = fallbackEngine
    }

    /// 预热的核心是尽早让 `AVAudioPlayer` 完成文件解析和缓冲准备。
    func warmUp() async throws {
        do {
            let player = try loadPlayer()
            player.prepareToPlay()
        } catch {
            if let fallbackEngine {
                // 即便兜底引擎能成功预热，也要把主链路失败原因写进日志，
                // 否则运营侧只会看到“一切正常”，难以发现已经在降级状态。
                logger.error("默认音频文件预热失败，已降级到兜底引擎：\(error.localizedDescription)")
                try await fallbackEngine.warmUp()
                return
            }

            throw error
        }
    }

    /// 真实文件时长会直接决定默认倒计时秒数，所以这里返回播放器解析出的 duration。
    func defaultSoundDuration() async throws -> TimeInterval {
        do {
            let player = try loadPlayer()
            return player.duration
        } catch {
            if let fallbackEngine {
                return try await fallbackEngine.defaultSoundDuration()
            }

            throw error
        }
    }

    /// 每次提醒都从头播放这段文件，避免停在上一次播放的中间位置。
    func playDefaultSound() async throws {
        do {
            let player = try loadPlayer()
            player.stop()
            player.currentTime = 0
            player.prepareToPlay()

            guard player.play() else {
                throw ReminderAudioEngineError.failedToStartPlayback(url: try resolveResourceURL())
            }
        } catch {
            if let fallbackEngine {
                try await fallbackEngine.playDefaultSound()
                return
            }

            throw error
        }
    }

    /// 停止文件播放器，同时把兜底播放器也一并停掉，避免旧状态残留。
    func stopPlayback() async {
        player?.stop()

        if let fallbackEngine {
            await fallbackEngine.stopPlayback()
        }
    }

    /// 惰性创建播放器；如果之前已经创建过，则直接复用。
    private func loadPlayer() throws -> AVAudioPlayer {
        if let player {
            return player
        }

        let resourceURL = try resolveResourceURL()

        do {
            let player = try AVAudioPlayer(contentsOf: resourceURL)
            player.volume = 1.0
            player.prepareToPlay()
            self.player = player
            return player
        } catch {
            throw ReminderAudioEngineError.failedToLoadBundledResource(
                url: resourceURL,
                underlyingError: error
            )
        }
    }

    /// 统一解析 bundle 内的默认音效 URL，并在第一次成功后缓存起来。
    private func resolveResourceURL() throws -> URL {
        if let cachedResourceURL {
            return cachedResourceURL
        }

        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
            throw ReminderAudioEngineError.missingBundledResource(
                name: resourceName,
                fileExtension: resourceExtension
            )
        }

        cachedResourceURL = url
        return url
    }
}

/// `GeneratedToneReminderAudioEngine` 使用程序生成的短提示音作为内建默认音效。
/// 这样既能保持“开箱即用”，又不需要额外维护二进制资源文件和打包配置。
@MainActor
final class GeneratedToneReminderAudioEngine: ReminderAudioEngine {
    /// AVFoundation 的音频图入口。
    private let engine: AVAudioEngine
    /// 真实负责播放 PCM 缓冲区的节点。
    private let playerNode: AVAudioPlayerNode
    /// 默认音效使用的单声道音频格式。
    private let format: AVAudioFormat
    /// 内建默认音效的目标时长。
    private let toneDuration: TimeInterval
    /// 默认提示音的频率；这里用较容易被人耳注意到的高频短音。
    private let frequency: Double
    /// 音量振幅；故意保持较低，避免首次接入时过于刺耳。
    private let amplitude: Float
    /// 标记音频图是否已经至少成功启动过一次。
    private var hasWarmedUp: Bool
    /// 统一日志通道，主要用于记录引擎启动失败和音频配置变更。
    private let logger = AppLogger(source: "ReminderAudioEngine.GeneratedTone")
    /// 监听 `AVAudioEngine.configurationChangeNotification` 的句柄，便于在 deinit 中精确移除。
    /// Swift 6 严格并发下，`deinit` 默认 nonisolated，访问 `(any NSObjectProtocol)?`
    /// 这种非 `Sendable` 的存储要么走 `MainActor.assumeIsolated`，要么标记 unsafe。
    /// 这里只在 init 写入、deinit 读取，写入后不会被外部并发访问，标 unsafe 是更直接的取舍。
    private nonisolated(unsafe) var configurationChangeObserver: NSObjectProtocol?

    /// 构造默认音频引擎，并把播放节点提前接到主混音器。
    init(
        toneDuration: TimeInterval = 1.0,
        frequency: Double = 880,
        amplitude: Float = 0.18
    ) {
        self.engine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        // 44100Hz 单声道是行业标准参数，AVFoundation 应始终支持；
        // 若构建失败说明 AVFoundation 环境严重异常，此处主动终止并输出诊断信息。
        guard let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else {
            preconditionFailure("无法创建 44100Hz 单声道音频格式：该格式是标准参数，失败意味着 AVFoundation 运行环境异常。")
        }
        self.format = audioFormat
        self.toneDuration = toneDuration
        self.frequency = frequency
        self.amplitude = amplitude
        self.hasWarmedUp = false

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.prepare()

        registerConfigurationChangeObserver()
    }

    /// 系统切换默认输出设备或采样率时 AVAudioEngine 会停掉自身，
    /// 这里把状态重置回未预热，下一次播放会强制走 reset+reconnect+start 路径。
    private func registerConfigurationChangeObserver() {
        // `AVAudioEngine` 文档明确说明该通知会在任意线程派发；
        // 这里把回调显式调度回 MainActor，匹配类型本身的隔离域。
        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleConfigurationChange()
            }
        }
    }

    /// 收到音频配置变化通知时清掉预热状态，避免继续使用已经失效的 IO 链路。
    private func handleConfigurationChange() {
        logger.error("AVAudioEngine 检测到音频配置变化，已标记需要重新预热")
        hasWarmedUp = false
    }

    deinit {
        if let configurationChangeObserver {
            NotificationCenter.default.removeObserver(configurationChangeObserver)
        }
    }

    /// 显式预热音频图，避免第一次提醒时才启动底层音频设备。
    func warmUp() async throws {
        try ensureEngineRunning()
        hasWarmedUp = true
    }

    /// 当前默认提示音时长就是调度层默认使用的倒计时秒数来源。
    func defaultSoundDuration() async throws -> TimeInterval {
        try await warmUp()
        return toneDuration
    }

    /// 每次播放前重新生成一个 PCM 缓冲区，避免复用同一缓冲区带来的生命周期问题。
    func playDefaultSound() async throws {
        try await warmUp()
        playerNode.stop()

        let buffer = makeToneBuffer()
        playerNode.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        playerNode.play()
    }

    /// 当会议被改期、取消或用户关闭提醒时，立即停止当前播放。
    func stopPlayback() async {
        playerNode.stop()
    }

    /// 确保底层 `AVAudioEngine` 已处于运行状态。
    /// 即使已经预热过，也仍要防御系统音频图被外部原因停止的情况。
    private func ensureEngineRunning() throws {
        if engine.isRunning {
            return
        }

        if hasWarmedUp {
            engine.reset()
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            engine.prepare()
        }

        do {
            try engine.start()
        } catch {
            // 把启动失败显式记录为错误，方便结合配置变化通知日志定位音频链路问题；
            // 仍然把异常抛出去，避免悄悄掩盖播放失败的事实。
            logger.error("AVAudioEngine 启动失败：\(error.localizedDescription)")
            throw error
        }
    }

    /// 生成一个带淡入淡出的正弦波缓冲区，减少纯方波式的“啪”声。
    private func makeToneBuffer() -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(format.sampleRate * toneDuration)
        // format 已在 init 中验证为合法格式，frameCapacity 为正整数；
        // 若此处返回 nil 说明 AVFoundation 状态异常，主动终止并输出诊断信息便于排查。
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            preconditionFailure("无法创建 PCM 缓冲区：format 与 frameCapacity 均为合法值，失败意味着 AVFoundation 运行时异常。")
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else {
            return buffer
        }

        let fadeFrameCount = max(1, min(Int(frameCount / 12), 1_024))
        let sampleRate = format.sampleRate

        for frame in 0 ..< Int(frameCount) {
            let time = Double(frame) / sampleRate
            let rawSample = sin(2 * Double.pi * frequency * time)
            let envelope: Double

            if frame < fadeFrameCount {
                envelope = Double(frame) / Double(fadeFrameCount)
            } else if frame >= Int(frameCount) - fadeFrameCount {
                envelope = Double(Int(frameCount) - frame) / Double(fadeFrameCount)
            } else {
                envelope = 1
            }

            channelData[frame] = Float(rawSample * envelope) * amplitude
        }

        return buffer
    }
}
