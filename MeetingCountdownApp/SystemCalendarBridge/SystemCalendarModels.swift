import Foundation

/// 这个文件定义系统日历桥接层对外暴露的稳定模型。
/// 它的目标是把 EventKit 的原始类型压成应用自己能长期持有的状态，
/// 这样 UI、偏好持久化和 `MeetingSource` 都不会直接依赖 `EKCalendar` / `EKEvent`。

/// `SystemCalendarAuthorizationState` 统一描述当前系统日历读取权限。
/// 这里故意不直接把 EventKit 的枚举暴露给 UI，因为界面只需要知道“能不能读”“为什么不能读”。
enum SystemCalendarAuthorizationState: Equatable, Sendable {
    case authorized
    case notDetermined
    case denied
    case restricted
    case writeOnly
    case unknown

    /// 标记当前状态是否允许读取系统日历事件。
    var allowsReading: Bool {
        switch self {
        case .authorized:
            return true
        case .notDetermined, .denied, .restricted, .writeOnly, .unknown:
            return false
        }
    }

    /// 给设置页和数据源健康状态提供统一说明。
    var summary: String {
        switch self {
        case .authorized:
            return "系统日历权限已授权，可读取 Calendar 事件"
        case .notDetermined:
            return "尚未决定是否允许访问日历"
        case .denied:
            return "系统日历权限已被拒绝，请先在系统设置中允许访问"
        case .restricted:
            return "系统日历权限受系统限制，当前无法读取"
        case .writeOnly:
            return "系统日历当前只有写入权限，无法读取已有事件"
        case .unknown:
            return "无法确认系统日历权限状态"
        }
    }

    /// 给 UI 提供短标签文案。
    var badgeText: String {
        switch self {
        case .authorized:
            return "已授权"
        case .notDetermined:
            return "待授权"
        case .denied, .restricted, .writeOnly:
            return "不可读"
        case .unknown:
            return "未知"
        }
    }
}

/// `SystemCalendarDescriptor` 描述一条可选的系统日历。
/// Phase 2 会把它展示在设置页的多选列表里，并根据 `isSuggestedByDefault` 做默认预选。
struct SystemCalendarDescriptor: Identifiable, Equatable, Sendable {
    /// 直接复用系统日历标识符作为稳定主键。
    let id: String
    /// 日历标题，例如“飞书日历”或“工作”。
    let title: String
    /// 日历来源名称，例如某个账户或 Calendar source。
    let sourceTitle: String
    /// 日历来源类型的用户可读文案，例如 `CalDAV`、`Exchange`。
    let sourceTypeLabel: String
    /// 当前是否建议作为默认预选候选。
    let isSuggestedByDefault: Bool

    /// 给设置页复用的副标题。
    var subtitle: String {
        if sourceTitle.isEmpty {
            return sourceTypeLabel
        }

        return "\(sourceTitle) · \(sourceTypeLabel)"
    }
}

/// `SystemCalendarEventPayload` 是 EventKit 事件被抽离出桥接层细节后的中间载荷。
/// 这样标准化测试可以只依赖这份纯 Swift 结构，而不需要直接构造 `EKEvent`。
struct SystemCalendarEventPayload: Equatable, Sendable {
    let identifier: String
    let title: String?
    let startAt: Date
    let endAt: Date
    let timeZoneIdentifier: String?
    let isAllDay: Bool
    let isCancelled: Bool
    let primaryURL: URL?
    let notes: String?
}

/// `SystemCalendarEventNormalizer` 负责把桥接层事件载荷转换成统一会议模型。
/// 这样 `SystemCalendarMeetingSource` 只负责 orchestration，不直接关心 URL 提取等细节。
enum SystemCalendarEventNormalizer {
    /// 把单条系统日历事件转换成 `MeetingRecord`。
    static func makeMeetingRecord(
        from payload: SystemCalendarEventPayload,
        calendar: SystemCalendarDescriptor
    ) -> MeetingRecord {
        MeetingRecord(
            id: payload.identifier,
            title: normalizedTitle(from: payload.title),
            startAt: payload.startAt,
            endAt: payload.endAt,
            timeZoneIdentifier: payload.timeZoneIdentifier ?? TimeZone.current.identifier,
            isAllDay: payload.isAllDay,
            isCancelled: payload.isCancelled,
            links: extractedLinks(primaryURL: payload.primaryURL, notes: payload.notes),
            source: MeetingSourceDescriptor(
                sourceIdentifier: calendar.id,
                displayName: calendar.title
            )
        )
    }

    /// 标题统一做去空白和兜底，避免菜单栏出现空标题。
    private static func normalizedTitle(from rawTitle: String?) -> String {
        let trimmedTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedTitle.isEmpty ? "未命名会议" : trimmedTitle
    }

    /// 从 `event.url` 和备注文本里提取链接，并按绝对地址去重。
    private static func extractedLinks(primaryURL: URL?, notes: String?) -> [MeetingLink] {
        var links: [MeetingLink] = []
        var seenURLs = Set<String>()

        if let primaryURL {
            appendLink(for: primaryURL, to: &links, seenURLs: &seenURLs)
        }

        let noteURLs = extractedURLs(from: notes ?? "")
        for url in noteURLs {
            appendLink(for: url, to: &links, seenURLs: &seenURLs)
        }

        return links
    }

    /// 通过 `NSDataDetector` 从备注中扫描所有 URL。
    private static func extractedURLs(from text: String) -> [URL] {
        guard !text.isEmpty else {
            return []
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) ?? []

        return matches.compactMap { $0.url }
    }

    /// 统一写入单条链接并按 URL 去重。
    private static func appendLink(for url: URL, to links: inout [MeetingLink], seenURLs: inout Set<String>) {
        let absoluteString = url.absoluteString

        guard seenURLs.insert(absoluteString).inserted else {
            return
        }

        links.append(
            MeetingLink(
                kind: guessedLinkKind(for: url),
                url: url
            )
        )
    }

    /// 目前先采用轻量启发式识别 VC 链接；识别不出来时回退成普通网页链接。
    private static func guessedLinkKind(for url: URL) -> MeetingLinkKind {
        let normalizedHost = (url.host ?? "").lowercased()
        let normalizedString = url.absoluteString.lowercased()

        if normalizedHost.contains("vc")
            || normalizedString.contains("meeting")
            || normalizedString.contains("video")
            || normalizedString.contains("lark")
            || normalizedString.contains("feishu") {
            return .vc
        }

        return .web
    }
}
