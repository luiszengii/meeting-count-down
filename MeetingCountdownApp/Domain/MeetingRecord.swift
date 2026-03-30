import Foundation

/// 这个文件承载应用的统一会议模型。
/// 设计重点不是一次性把所有来源字段搬全，而是定义提醒引擎真正依赖的最小公共集合：
/// 会议何时开始、是否全天、是否已取消、有哪些链接、来自哪种数据源。
/// 后续具体接入可以把额外原始信息放进 `metadata`，但不能跳过这里直接把原始模型送进提醒层。

struct MeetingRecord: Identifiable, Equatable, Sendable {
    /// `id` 是统一会议主键。
    /// 它不要求和上游平台字段同名，但必须在当前来源内稳定，方便列表 diff、排序和调度取消。
    let id: String
    /// 菜单栏和设置页默认展示的会议标题。
    var title: String
    /// 会议开始时间，是提醒调度最核心的时间点。
    var startAt: Date
    /// 会议结束时间，当前主要用于展示和后续过滤扩展。
    var endAt: Date
    /// 保存会议原始时区，避免未来跨时区时只剩一个绝对时间而丢失语义。
    var timeZoneIdentifier: String
    /// 全天事件通常不进入会前提醒，所以这里需要显式标记。
    var isAllDay: Bool
    /// 已取消会议必须能被快速过滤掉，否则会造成误提醒。
    var isCancelled: Bool
    /// 从原始会议记录里提取出来的可点击链接，例如飞书视频会议或网页详情。
    var links: [MeetingLink]
    /// 记录会议来自哪一路接入，方便诊断、展示和后续回跳。
    var source: MeetingSourceDescriptor
    /// 记录当前用户对会议的响应状态，后续可支持“只提醒已接受会议”。
    var attendeeResponse: MeetingParticipantResponseStatus
    /// 兜底原始字段存放区。
    /// 当某一路接入暂时还没有完整建模时，可以把额外信息先放这里，避免丢数据。
    var metadata: [String: String]

    /// 统一会议模型的指定初始化器。
    /// 大多数参数都给了默认值，目的是让不同接入方式在逐步接入字段时不会被过早迫使一次性填满全部信息。
    init(
        id: String,
        title: String,
        startAt: Date,
        endAt: Date,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        isAllDay: Bool = false,
        isCancelled: Bool = false,
        links: [MeetingLink] = [],
        source: MeetingSourceDescriptor,
        attendeeResponse: MeetingParticipantResponseStatus = .unknown,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.isAllDay = isAllDay
        self.isCancelled = isCancelled
        self.links = links
        self.source = source
        self.attendeeResponse = attendeeResponse
        self.metadata = metadata
    }
}

/// 统一表达“从会议里提取出来的可点击链接”。
struct MeetingLink: Equatable, Sendable {
    /// 链接类型告诉 UI 这是入会链接、网页链接还是事件详情。
    var kind: MeetingLinkKind
    /// 真实可打开的 URL。
    var url: URL
}

/// 统一限制链接的语义种类，避免上层只拿到一个裸 URL 后不知道它应该如何使用。
enum MeetingLinkKind: String, Codable, Equatable, Sendable {
    /// 视频会议或语音会议的直接加入链接。
    case vc
    /// 普通网页链接。
    case web
    /// 指向会议详情页或原始事件详情页的链接。
    case eventDetail
    /// 暂时无法识别类型时的保底值。
    case unknown
}

/// 统一记录用户对会议的响应状态，方便后续做“仅提醒已接受会议”之类的过滤规则。
enum MeetingParticipantResponseStatus: String, Codable, Equatable, Sendable {
    /// 用户已明确接受会议。
    case accepted
    /// 用户暂定参加。
    case tentative
    /// 用户尚未回应。
    case needsAction
    /// 用户已拒绝会议。
    case declined
    /// 上游没有提供明确响应状态时的保底值。
    case unknown
}

/// 描述当前会议记录来自哪一种上游源，以及在该源内的标识信息。
struct MeetingSourceDescriptor: Equatable, Sendable {
    /// 会议来自哪一种连接模式，例如 CalDAV 或 BYO Feishu App。
    var mode: ConnectionMode
    /// 该来源内部的唯一标识，可用于日志和诊断。
    var sourceIdentifier: String
    /// 面向用户展示的来源名称。
    var displayName: String
}
