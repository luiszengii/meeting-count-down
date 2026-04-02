import Foundation

/// `SoundProfile` 描述一条可被提醒引擎或设置页消费的提醒音频。
/// 它只保存“展示需要什么”和“如何重新定位这条音频”，不直接持有播放器对象。
struct SoundProfile: Identifiable, Equatable, Codable, Sendable {
    /// `Storage` 描述音频内容实际来自哪里。
    /// 当前只区分“内建 bundle 资源”和“用户导入到本地目录的文件”两类。
    enum Storage: Equatable, Codable, Sendable {
        /// app 自带的默认提醒音频。
        case bundled(resourceName: String, resourceExtension: String)
        /// 用户上传后复制到 app 自己管理目录里的音频文件。
        case imported(fileName: String)
    }

    /// 内建默认提醒音频的稳定 ID。
    static let bundledDefaultID = "sound-profile.bundled-default"
    /// 内建默认提醒音频的展示名。
    static let bundledDefaultDisplayName = "PS5 Game Start"
    /// 当前内建默认提醒音频在 bundle 里的资源名。
    static let bundledDefaultResourceName = "PS5 Game Start"
    /// 当前内建默认提醒音频在 bundle 里的扩展名。
    static let bundledDefaultResourceExtension = "flac"

    /// 这条音频在 app 内部的稳定主键。
    let id: String
    /// 列表里展示给用户看的名称。
    let displayName: String
    /// 这条音频如何被重新定位到真实文件。
    let storage: Storage
    /// 这条音频的时长，供设置页展示和默认倒计时计算复用。
    let duration: TimeInterval
    /// 记录创建时间，方便未来扩展排序或调试。
    let createdAt: Date

    /// 显式初始化器，避免调用方反复手写所有字段。
    init(
        id: String,
        displayName: String,
        storage: Storage,
        duration: TimeInterval,
        createdAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.storage = storage
        self.duration = duration
        self.createdAt = createdAt
    }

    /// 当前是否是 app 自带的默认提醒音频。
    var isBundledDefault: Bool {
        id == Self.bundledDefaultID
    }

    /// 当前是否是用户导入的音频。
    var isImported: Bool {
        if case .imported = storage {
            return true
        }

        return false
    }

    /// 把音频时长压成设置页更容易扫读的短文案。
    var durationLine: String {
        Self.formatDuration(duration)
    }

    /// 构造当前 app 固定存在的内建默认提醒音频条目。
    static func bundledDefault(duration: TimeInterval) -> SoundProfile {
        SoundProfile(
            id: bundledDefaultID,
            displayName: bundledDefaultDisplayName,
            storage: .bundled(
                resourceName: bundledDefaultResourceName,
                resourceExtension: bundledDefaultResourceExtension
            ),
            duration: duration,
            createdAt: .distantPast
        )
    }

    /// 把持久化层里保存的用户音频和当前内建默认音频合并成最终列表。
    /// 默认音频始终放在第一位，用户导入项保留既有顺序。
    static func mergedWithBundledDefault(
        _ storedProfiles: [SoundProfile],
        bundledDefault: SoundProfile
    ) -> [SoundProfile] {
        let importedProfiles = storedProfiles.filter(\.isImported)
        return [bundledDefault] + importedProfiles
    }

    /// 统一格式化音频时长，避免设置页自己拼分钟和秒。
    private static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(1, Int(ceil(duration)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes == 0 {
            return "\(seconds) 秒"
        }

        if seconds == 0 {
            return "\(minutes) 分钟"
        }

        return "\(minutes) 分 \(seconds) 秒"
    }
}
