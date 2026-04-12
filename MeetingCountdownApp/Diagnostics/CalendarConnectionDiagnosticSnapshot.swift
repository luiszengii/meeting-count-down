import Foundation

/// `CalendarConnectionDiagnosticSnapshot` 把“为什么 app 仍然判定接入未完成”所需的只读事实压成一份稳定快照。
/// 它不会主动触发权限申请或刷新，只负责把当前权限、候选日历、已保存选择和聚合健康状态整理成
/// 可复制、可粘贴的文本，方便测试用户直接把问题现场反馈给维护者。
struct CalendarConnectionDiagnosticSnapshot: Equatable, Sendable {
    /// 这份快照是在什么时候生成的。
    let generatedAt: Date
    /// 当前运行中 app 的 bundle identifier。
    let bundleIdentifier: String
    /// 当前 app 的营销版本号。
    let appVersion: String
    /// 当前 app 的构建号。
    let buildNumber: String
    /// EventKit / 系统日历权限状态。
    let authorizationState: SystemCalendarAuthorizationState
    /// 会议源聚合后的健康状态。
    let healthState: SourceHealthState
    /// 最近一次刷新失败时的用户可见错误。
    let lastSourceErrorMessage: String?
    /// 最近一次成功刷新会议源的时间。
    let lastSourceRefreshAt: Date?
    /// 最近一次重载系统日历候选列表的时间。
    let lastCalendarStateLoadAt: Date?
    /// 当前是否已经有过显式保存的系统日历选择。
    let hasStoredCalendarSelection: Bool
    /// 最近一次读取到的持久化日历 ID。
    let storedSelectedCalendarIDs: [String]
    /// 最近一次从持久化里读到、但当前系统里已经不存在的日历 ID。
    let unavailableStoredCalendarIDs: [String]
    /// 当前真正参与提醒的日历 ID。
    let effectiveSelectedCalendarIDs: [String]
    /// 当前系统里枚举到的候选日历。
    let availableCalendars: [SystemCalendarDescriptor]

    /// 统一输出给用户复制的只读诊断文本。
    /// 它的重点不是“好看”，而是让维护者能快速看出：
    /// 1. 权限是否真的给到这个 app；
    /// 2. 当前有没有枚举到系统日历；
    /// 3. 已保存选择是否和当前候选列表失配。
    var reportText: String {
        var lines: [String] = [
            "bundle_identifier: \(bundleIdentifier)",
            "app_version: \(appVersion) (\(buildNumber))",
            "generated_at_utc: \(Self.formattedDate(generatedAt))",
            "authorization_state: \(authorizationState.debugLabel)",
            "authorization_summary: \(authorizationState.summary)",
            "source_health_state: \(healthState.debugLabel)",
            "source_health_summary: \(healthState.summary)",
            "last_source_error: \(lastSourceErrorMessage ?? "none")",
            "last_source_refresh_at_utc: \(Self.formattedDate(lastSourceRefreshAt))",
            "last_calendar_state_load_at_utc: \(Self.formattedDate(lastCalendarStateLoadAt))",
            "selection_debug_state: \(selectionDebugState)",
            "has_stored_calendar_selection: \(hasStoredCalendarSelection)",
            "stored_selected_calendar_ids: \(Self.joinedValue(storedSelectedCalendarIDs))",
            "unavailable_stored_calendar_ids: \(Self.joinedValue(unavailableStoredCalendarIDs))",
            "effective_selected_calendar_ids: \(Self.joinedValue(effectiveSelectedCalendarIDs))",
            "available_calendar_count: \(availableCalendars.count)"
        ]

        if availableCalendars.isEmpty {
            lines.append("available_calendars: none")
        } else {
            lines.append("available_calendars:")
            for calendar in availableCalendars {
                lines.append("- \(calendar.debugSummary(selectedCalendarIDs: Set(effectiveSelectedCalendarIDs)))")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// 这个字段专门帮助维护者区分“从没选过日历”“选过但当前都失配了”“当前已经生效”这三种高频状态。
    var selectionDebugState: String {
        if !effectiveSelectedCalendarIDs.isEmpty {
            return "ready"
        }

        if !unavailableStoredCalendarIDs.isEmpty {
            return "stored_selection_missing_from_current_calendar_list"
        }

        if hasStoredCalendarSelection {
            return "stored_selection_is_empty"
        }

        return "selection_not_saved_yet"
    }

    /// 用统一 UTC 文本避免用户截图里的本地格式差异。
    private static func formattedDate(_ date: Date?) -> String {
        guard let date else {
            return "none"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        return formatter.string(from: date)
    }

    /// 把数组压成单行字符串；空数组时显式返回 `none`，避免维护者误会成字段缺失。
    private static func joinedValue(_ values: [String]) -> String {
        let sortedValues = values.sorted()
        return sortedValues.isEmpty ? "none" : sortedValues.joined(separator: ", ")
    }
}

private extension SystemCalendarAuthorizationState {
    /// 诊断快照需要稳定、可 grep 的短标签，而不是只靠用户界面翻译文案。
    var debugLabel: String {
        switch self {
        case .authorized:
            return "authorized"
        case .notDetermined:
            return "not_determined"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .writeOnly:
            return "write_only"
        case .unknown:
            return "unknown"
        }
    }
}

private extension SourceHealthState {
    /// 和授权状态一样，这里输出稳定短标签，方便维护者快速分组问题。
    var debugLabel: String {
        switch self {
        case .unconfigured:
            return "unconfigured"
        case .ready:
            return "ready"
        case .warning:
            return "warning"
        case .failed:
            return "failed"
        }
    }
}

private extension SystemCalendarDescriptor {
    /// 把单条系统日历描述符压成单行，尽量保留 title、source 和 id 三个对排查最有价值的字段。
    func debugSummary(selectedCalendarIDs: Set<String>) -> String {
        var flags: [String] = []

        if selectedCalendarIDs.contains(id) {
            flags.append("selected")
        }

        if isSuggestedByDefault {
            flags.append("suggested")
        }

        let sourceValue = sourceTitle.isEmpty ? "none" : sourceTitle
        let flagValue = flags.isEmpty ? "none" : flags.joined(separator: ",")

        return "\(title) | source=\(sourceValue) | type=\(sourceTypeLabel) | id=\(id) | flags=\(flagValue)"
    }
}
