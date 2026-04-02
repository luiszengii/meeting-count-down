import Foundation

/// `NextMeetingSelecting` 负责从规范化后的会议列表里挑出下一场会议。
/// 这里明确把“选择规则”从 UI 和数据源实现里抽出来，避免未来每个接入方式都各自判断一次。
/// 当前规则固定为：从未来会议中选择最近的一场，跳过全天事件和已取消事件。

protocol NextMeetingSelecting: Sendable {
    /// 在给定当前时间的前提下，从规范化会议列表里选择“下一场会议”。
    /// 这里把 `now` 作为显式参数传入，目的是让规则层更易测试，也避免内部偷偷依赖真实时钟。
    func selectNextMeeting(
        from meetings: [MeetingRecord],
        now: Date,
        reminderPreferences: ReminderPreferences
    ) -> MeetingRecord?
}

struct DefaultNextMeetingSelector: NextMeetingSelecting {
    /// 先过滤掉不应进入提醒候选集的会议，再按时间和稳定次序排序。
    func selectNextMeeting(
        from meetings: [MeetingRecord],
        now: Date,
        reminderPreferences: ReminderPreferences
    ) -> MeetingRecord? {
        meetings
            .filter { meeting in
                shouldInclude(meeting: meeting, now: now, reminderPreferences: reminderPreferences)
            }
            .sorted(by: Self.sortMeetings)
            .first
    }

    /// 统一收拢“下一场会议”候选过滤规则，避免以后把过滤条件散落到协调层或视图层。
    private func shouldInclude(
        meeting: MeetingRecord,
        now: Date,
        reminderPreferences: ReminderPreferences
    ) -> Bool {
        guard meeting.startAt >= now else {
            return false
        }

        guard !meeting.isAllDay, !meeting.isCancelled else {
            return false
        }

        if reminderPreferences.onlyForMeetingsWithVideoLink && !meeting.hasVideoConferenceLink {
            return false
        }

        if reminderPreferences.skipDeclinedMeetings && meeting.isDeclinedByCurrentUser {
            return false
        }

        return true
    }

    /// 当两场会议都满足候选条件时，优先按开始时间排序；如果时间完全相同，再按稳定 id 排序。
    private static func sortMeetings(lhs: MeetingRecord, rhs: MeetingRecord) -> Bool {
        if lhs.startAt != rhs.startAt {
            return lhs.startAt < rhs.startAt
        }

        return lhs.id < rhs.id
    }
}

protocol DateProviding: Sendable {
    /// 返回调用方定义语义下的“当前时间”。
    func now() -> Date
}

struct SystemDateProvider: DateProviding {
    /// 生产环境里直接使用系统时间，实现最简单的真实时钟。
    func now() -> Date {
        Date()
    }
}
