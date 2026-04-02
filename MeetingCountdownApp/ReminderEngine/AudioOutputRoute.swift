import CoreAudio
import Foundation

/// 这个文件负责把 macOS 当前默认音频输出设备压缩成提醒模块可消费的最小语义。
/// 提醒引擎并不需要知道 CoreAudio 的完整设备图，它只关心：
/// “当前默认输出能不能被安全视为耳机等私密收听设备”。

/// `AudioOutputRouteKind` 只表达提醒策略真正需要的三种结论。
enum AudioOutputRouteKind: Equatable, Sendable {
    /// 明确可视为耳机、蓝牙耳机、AirPods 一类私密输出。
    case privateListening
    /// 明确更像外放、显示器或公共播音设备。
    case speakerLike
    /// 无法安全判断设备语义时的保守兜底值。
    case unknown
}

/// `AudioOutputRouteSnapshot` 描述当前默认输出设备的最小快照。
/// 当前主要为了日志、调试和“仅耳机时播放”的提醒策略服务。
struct AudioOutputRouteSnapshot: Equatable, Sendable {
    /// 当前默认输出设备的人类可读名称。
    let name: String
    /// 当前默认输出对提醒策略而言的归类结果。
    let kind: AudioOutputRouteKind
}

/// `AudioOutputRouteProviding` 把“如何读取默认输出设备”从提醒引擎里剥离出来。
/// 测试可以用 stub 注入固定路由，生产环境再用真实 CoreAudio 实现。
@MainActor
protocol AudioOutputRouteProviding: AnyObject {
    /// 返回当前默认输出设备的最小快照。
    func currentRoute() -> AudioOutputRouteSnapshot
}

/// `CoreAudioOutputRouteProvider` 负责读取 macOS 当前默认输出设备，并把它保守地分类。
/// 它优先看设备名称里的明显关键词，再看 transport type，避免把插着有线耳机的内建设备误判成外放。
@MainActor
final class CoreAudioOutputRouteProvider: AudioOutputRouteProviding {
    func currentRoute() -> AudioOutputRouteSnapshot {
        guard let deviceID = defaultOutputDeviceID() else {
            return AudioOutputRouteSnapshot(name: "未知输出设备", kind: .unknown)
        }

        let deviceName = deviceName(for: deviceID) ?? "未知输出设备"
        let transportType = transportType(for: deviceID)

        return AudioOutputRouteSnapshot(
            name: deviceName,
            kind: Self.classify(name: deviceName, transportType: transportType)
        )
    }

    /// 按“名称关键词优先、transport type 兜底”的顺序保守分类当前输出设备。
    static func classify(name: String, transportType: UInt32?) -> AudioOutputRouteKind {
        let normalizedName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if privateListeningKeywords.contains(where: normalizedName.contains) {
            return .privateListening
        }

        if speakerLikeKeywords.contains(where: normalizedName.contains) {
            return .speakerLike
        }

        guard let transportType else {
            return .unknown
        }

        switch transportType {
        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE:
            return .privateListening

        case kAudioDeviceTransportTypeBuiltIn,
             kAudioDeviceTransportTypeHDMI,
             kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeAirPlay:
            return .speakerLike

        default:
            return .unknown
        }
    }

    /// 读取当前默认输出设备 ID。
    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID.zero
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr else {
            return nil
        }

        return deviceID
    }

    /// 读取设备展示名称；如果失败则返回 `nil`，由调用方决定如何兜底。
    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceName: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &deviceName)

        guard status == noErr else {
            return nil
        }

        return deviceName as String
    }

    /// 读取设备 transport type，供名称无法判断时做保守兜底。
    private func transportType(for deviceID: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType = UInt32.zero
        var size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transportType)

        guard status == noErr else {
            return nil
        }

        return transportType
    }

    /// 明确更像耳机或私密收听设备的关键词。
    private static let privateListeningKeywords = [
        "airpods",
        "headphone",
        "headphones",
        "headset",
        "earbud",
        "earbuds",
        "earphone",
        "earphones",
        "pods",
        "buds"
    ]

    /// 明确更像外放、显示器或共享播音设备的关键词。
    private static let speakerLikeKeywords = [
        "speaker",
        "speakers",
        "display",
        "monitor",
        "homepod",
        "soundbar",
        "tv",
        "hdmi"
    ]
}
