import Foundation

/// `SystemCalendarMeetingSource` 是 Phase 2 真正接入 `SourceCoordinator` 的 CalDAV / 系统日历数据源。
/// 它不直接做 UI，也不直接管理权限按钮；它只根据“当前权限状态 + 已选系统日历”
/// 决定健康状态，并在允许读取时拉取系统 Calendar 里的事件。
@MainActor
final class SystemCalendarMeetingSource: MeetingSource {
    /// 这是协调层和日志里看到的全局来源描述。
    let descriptor: MeetingSourceDescriptor

    /// EventKit 桥接层。
    private let calendarAccess: any SystemCalendarAccessing
    /// 非敏感配置持久化入口。
    private let preferencesStore: any PreferencesStore
    /// 读取窗口向过去回溯的秒数。
    private let lookbackInterval: TimeInterval
    /// 读取窗口向未来展开的秒数。
    private let lookaheadInterval: TimeInterval

    init(
        calendarAccess: any SystemCalendarAccessing,
        preferencesStore: any PreferencesStore,
        descriptor: MeetingSourceDescriptor = MeetingSourceDescriptor(
            sourceIdentifier: "system-calendar-caldav",
            displayName: "CalDAV / 系统日历"
        ),
        lookbackInterval: TimeInterval = 30 * 60,
        lookaheadInterval: TimeInterval = 24 * 60 * 60
    ) {
        self.calendarAccess = calendarAccess
        self.preferencesStore = preferencesStore
        self.descriptor = descriptor
        self.lookbackInterval = lookbackInterval
        self.lookaheadInterval = lookaheadInterval
    }

    /// 健康状态只看三件事：权限、已选日历和当前系统日历是否还存在。
    func healthState() async -> SourceHealthState {
        let authorizationState = calendarAccess.currentAuthorizationState()

        guard authorizationState.allowsReading else {
            return .unconfigured(message: authorizationState.summary)
        }

        let selectedCalendarIDs = await preferencesStore.loadSelectedSystemCalendarIDs()

        guard !selectedCalendarIDs.isEmpty else {
            return .unconfigured(message: "尚未选择需要纳入提醒的系统日历")
        }

        let availableCalendars = calendarAccess.fetchCalendars()
        let availableCalendarIDs = Set(availableCalendars.map(\.id))
        let matchedSelection = selectedCalendarIDs.intersection(availableCalendarIDs)

        guard !matchedSelection.isEmpty else {
            return .unconfigured(message: "已选系统日历当前不可用，请重新选择")
        }

        return .ready(message: "已连接 \(matchedSelection.count) 个系统日历")
    }

    /// 读取选中的系统日历事件，并统一标准化成 `MeetingRecord` 列表。
    func refresh(trigger: RefreshTrigger, now: Date) async throws -> SourceSyncSnapshot {
        let authorizationState = calendarAccess.currentAuthorizationState()

        guard authorizationState.allowsReading else {
            throw MeetingSourceError.notConfigured(message: authorizationState.summary)
        }

        let selectedCalendarIDs = await preferencesStore.loadSelectedSystemCalendarIDs()

        guard !selectedCalendarIDs.isEmpty else {
            throw MeetingSourceError.notConfigured(message: "尚未选择需要纳入提醒的系统日历")
        }

        let start = now.addingTimeInterval(-lookbackInterval)
        let end = now.addingTimeInterval(lookaheadInterval)

        do {
            let calendarEvents = try calendarAccess.fetchEventPayloads(
                start: start,
                end: end,
                calendarIDs: selectedCalendarIDs
            )

            guard !calendarEvents.isEmpty else {
                return SourceSyncSnapshot(
                    source: descriptor,
                    meetings: [],
                    healthState: .ready(message: "已连接 \(selectedCalendarIDs.count) 个系统日历，当前暂无可提醒会议"),
                    refreshedAt: now
                )
            }

            let meetings = calendarEvents.map { item in
                SystemCalendarEventNormalizer.makeMeetingRecord(
                    from: item.payload,
                    calendar: item.calendar
                )
            }

            return SourceSyncSnapshot(
                source: descriptor,
                meetings: meetings,
                healthState: .ready(message: "已从 \(selectedCalendarIDs.count) 个系统日历读取会议"),
                refreshedAt: now
            )
        } catch let error as MeetingSourceError {
            throw error
        } catch {
            throw MeetingSourceError.unavailable(message: "读取系统日历失败：\(error.localizedDescription)")
        }
    }
}
