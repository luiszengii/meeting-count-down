import EventKit
import Foundation

/// 这个文件承载系统日历桥接层和 EventKit 的真实交互。
/// 这里负责读取权限状态、申请访问、枚举系统日历，并把 `EKEvent` 抽离成纯 Swift 载荷。

/// `SystemCalendarAccessing` 定义系统日历桥接层对上游暴露的稳定能力。
/// 设置页控制器和 MeetingSource 都依赖这份协议，而不是直接依赖 EventKit。
@MainActor
protocol SystemCalendarAccessing: AnyObject {
    /// 返回当前系统日历读取权限。
    func currentAuthorizationState() -> SystemCalendarAuthorizationState
    /// 触发显式的系统日历权限申请。
    func requestReadAccess() async throws -> SystemCalendarAuthorizationState
    /// 枚举当前机器里所有可见的事件日历。
    func fetchCalendars() -> [SystemCalendarDescriptor]
    /// 读取指定系统日历在某个时间窗口内的事件载荷。
    func fetchEventPayloads(
        start: Date,
        end: Date,
        calendarIDs: Set<String>
    ) throws -> [(calendar: SystemCalendarDescriptor, payload: SystemCalendarEventPayload)]
}

/// `EventKitSystemCalendarAccess` 是当前真实的 EventKit 桥接实现。
/// 它内部持有单个 `EKEventStore`，供权限申请、日历枚举和事件读取复用。
@MainActor
final class EventKitSystemCalendarAccess: SystemCalendarAccessing {
    /// EventKit 的统一入口对象。
    /// `EKEventStore` 会长期跟随这个桥接对象存活，但调用方仍通过 `@MainActor` 入口串行访问它。
    /// 这里显式使用 `nonisolated(unsafe)`，避免 Swift 6 把异步权限申请误判成跨 actor 发送。
    nonisolated(unsafe) private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    /// 读取当前权限并映射成应用自己的授权状态。
    func currentAuthorizationState() -> SystemCalendarAuthorizationState {
        Self.authorizationState(
            from: EKEventStore.authorizationStatus(for: .event)
        )
    }

    /// 由设置页显式触发系统权限弹窗。
    func requestReadAccess() async throws -> SystemCalendarAuthorizationState {
        _ = try await eventStore.requestFullAccessToEvents()
        return currentAuthorizationState()
    }

    /// 枚举所有可用于读取事件的系统日历，并统一排序。
    func fetchCalendars() -> [SystemCalendarDescriptor] {
        eventStore.calendars(for: .event)
            .map(Self.calendarDescriptor(from:))
            .sorted(by: Self.sortCalendars)
    }

    /// 先把选中的系统日历 ID 映射成真实 `EKCalendar`，再读取给定时间窗口内的事件。
    func fetchEventPayloads(
        start: Date,
        end: Date,
        calendarIDs: Set<String>
    ) throws -> [(calendar: SystemCalendarDescriptor, payload: SystemCalendarEventPayload)] {
        guard !calendarIDs.isEmpty else {
            return []
        }

        let calendars = eventStore.calendars(for: .event)
        let matchedCalendars = calendars.filter { calendarIDs.contains($0.calendarIdentifier) }
        let calendarDescriptorsByID = Dictionary(
            uniqueKeysWithValues: matchedCalendars.map { calendar in
                (calendar.calendarIdentifier, Self.calendarDescriptor(from: calendar))
            }
        )

        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: matchedCalendars)
        let events = eventStore.events(matching: predicate)
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate {
                    return lhs.startDate < rhs.startDate
                }

                return (lhs.eventIdentifier ?? lhs.title ?? "") < (rhs.eventIdentifier ?? rhs.title ?? "")
            }

        return events.compactMap { event in
            guard
                let calendarDescriptor = calendarDescriptorsByID[event.calendar.calendarIdentifier]
            else {
                return nil
            }

            return (
                calendar: calendarDescriptor,
                payload: Self.eventPayload(from: event)
            )
        }
    }

    /// 把 EventKit 授权状态映射成应用自己的桥接状态。
    static func authorizationState(from status: EKAuthorizationStatus) -> SystemCalendarAuthorizationState {
        switch status {
        case .fullAccess:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .writeOnly:
            return .writeOnly
        @unknown default:
            return .unknown
        }
    }

    /// 把 `EKCalendar` 折叠成 UI 和偏好层都能持有的描述符。
    private static func calendarDescriptor(from calendar: EKCalendar) -> SystemCalendarDescriptor {
        let sourceTitle = calendar.source.title.trimmingCharacters(in: .whitespacesAndNewlines)

        return SystemCalendarDescriptor(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            sourceTitle: sourceTitle,
            sourceTypeLabel: sourceTypeLabel(for: calendar.source.sourceType),
            isSuggestedByDefault: shouldSuggestCalendar(sourceTitle: sourceTitle)
        )
    }

    /// 把 `EKEvent` 抽离成纯 Swift 事件载荷。
    private static func eventPayload(from event: EKEvent) -> SystemCalendarEventPayload {
        let fallbackIdentifier = [
            event.calendar.calendarIdentifier,
            String(event.startDate.timeIntervalSince1970),
            event.title ?? "untitled"
        ].joined(separator: "::")

        return SystemCalendarEventPayload(
            identifier: event.eventIdentifier ?? fallbackIdentifier,
            title: event.title,
            startAt: event.startDate,
            endAt: event.endDate,
            timeZoneIdentifier: event.timeZone?.identifier,
            isAllDay: event.isAllDay,
            isCancelled: event.status == .canceled,
            attendeeResponse: currentUserResponse(from: event),
            primaryURL: event.url,
            notes: event.notes
        )
    }

    /// 尝试从 EventKit 参与者列表里找出“当前用户”这一项，并把它映射成统一响应状态。
    /// 如果上游没有暴露当前用户或状态语义不够明确，就回退成 `.unknown`，避免误过滤会议。
    private static func currentUserResponse(from event: EKEvent) -> MeetingParticipantResponseStatus {
        guard let currentUserParticipant = event.attendees?.first(where: \.isCurrentUser) else {
            return .unknown
        }

        switch currentUserParticipant.participantStatus {
        case .accepted:
            return .accepted
        case .tentative:
            return .tentative
        case .pending:
            return .needsAction
        case .declined:
            return .declined
        case .delegated, .completed, .inProcess, .unknown:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    /// 对用户最关键的是先看到“推荐默认选中的日历”，再看到其它候选。
    private static func sortCalendars(lhs: SystemCalendarDescriptor, rhs: SystemCalendarDescriptor) -> Bool {
        if lhs.isSuggestedByDefault != rhs.isSuggestedByDefault {
            return lhs.isSuggestedByDefault && !rhs.isSuggestedByDefault
        }

        if lhs.title != rhs.title {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }

        return lhs.id < rhs.id
    }

    /// 把 EventKit source type 压成用户能看懂的短标签。
    private static func sourceTypeLabel(for sourceType: EKSourceType) -> String {
        switch sourceType {
        case .local:
            return "本地"
        case .exchange:
            return "Exchange"
        case .calDAV:
            return "CalDAV"
        case .mobileMe:
            return "iCloud"
        case .subscribed:
            return "订阅"
        case .birthdays:
            return "生日"
        @unknown default:
            return "其他"
        }
    }

    /// 当前默认预选策略只认飞书 CalDAV 账户本身，避免把用户的其它 CalDAV / iCloud 日历都误标成推荐。
    static func shouldSuggestCalendar(sourceTitle: String) -> Bool {
        let normalizedSourceTitle = sourceTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return normalizedSourceTitle.contains("caldav.feishu.cn")
    }
}
