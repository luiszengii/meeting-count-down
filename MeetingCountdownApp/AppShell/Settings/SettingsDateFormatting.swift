import Foundation
import SwiftUI

// MARK: - Date / time formatting helpers

/// Formatter 集合和所有日期 / 时长的文案推导。
/// 这里只做格式化，不改变任何业务规则或状态判断。
///
/// 2026-04-22 拆分自 Presentation.swift（见 ADR: docs/adrs/2026-04-22-presentation-split.md）
extension SettingsView {

    // MARK: Static formatters

    static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let englishMonthSymbols = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    // MARK: Date headline

    /// "今天 17:27" 这种时间表达比单独的时分更清晰，跨天时也不会让用户误判。
    func localizedDateHeadline(for date: Date) -> String {
        let timeLine = Self.absoluteFormatter.string(from: date)
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return localized("今天 \(timeLine)", "Today \(timeLine)")
        }

        if calendar.isDateInTomorrow(date) {
            return localized("明天 \(timeLine)", "Tomorrow \(timeLine)")
        }

        if calendar.isDateInYesterday(date) {
            return localized("昨天 \(timeLine)", "Yesterday \(timeLine)")
        }

        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)

        if uiLanguage == .english {
            return "\(Self.englishMonthSymbols[max(0, min(11, month - 1))]) \(day), \(timeLine)"
        }

        let currentYear = calendar.component(.year, from: Date())
        let year = calendar.component(.year, from: date)

        if year == currentYear {
            return "\(month)月\(day)日 \(timeLine)"
        }

        return "\(year)年\(month)月\(day)日 \(timeLine)"
    }

    // MARK: Meeting time lines

    func localizedMeetingStartLine(for meeting: MeetingRecord) -> String {
        "\(Self.absoluteFormatter.string(from: meeting.startAt)) (\(localizedCountdownLine(until: meeting.startAt)))"
    }

    func localizedCountdownLine(until date: Date) -> String {
        let interval = max(0, date.timeIntervalSinceNow)

        if interval < 60 {
            return localized("即将开始", "Starting Soon")
        }

        let totalSeconds = Int(interval.rounded(.up))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if uiLanguage == .english {
            if hours > 0 {
                return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
            }

            return "\(max(1, minutes))m"
        }

        if hours > 0 {
            return minutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes) 分钟"
        }

        return "\(max(1, minutes)) 分钟"
    }

    /// Overview 主卡把开始时间表达成"今天 / 明天 / 日期 + 时间"的组合，更贴近用户视角。
    func localizedMeetingScheduleLine(for meeting: MeetingRecord) -> String {
        localizedDateHeadline(for: meeting.startAt)
    }

    func localizedMeetingCountdownHeadline(for meeting: MeetingRecord) -> String {
        let interval = max(0, meeting.startAt.timeIntervalSinceNow)

        guard interval >= 60 else {
            return localized("距离开始不到 1 分钟", "Starts in less than 1 minute")
        }

        return localized(
            "距离开始还有 \(localizedFutureDurationDescription(interval))",
            "Starts in \(localizedFutureDurationDescription(interval))"
        )
    }

    // MARK: Duration & elapsed time

    func localizedElapsedDescription(_ elapsed: TimeInterval) -> String {
        let totalMinutes = max(1, Int(elapsed / 60))

        if uiLanguage == .english {
            guard totalMinutes >= 60 else {
                return totalMinutes == 1 ? "1 minute" : "\(totalMinutes) minutes"
            }

            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if minutes == 0 {
                return hours == 1 ? "1 hour" : "\(hours) hours"
            }

            return "\(hours)h \(minutes)m"
        }

        guard totalMinutes >= 60 else {
            return "\(totalMinutes) 分钟"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if minutes == 0 {
            return "\(hours) 小时"
        }

        return "\(hours) 小时 \(minutes) 分钟"
    }

    /// `SoundProfile.durationLine` 仍然是偏业务层的文案，这里只负责外壳本地化显示。
    func localizedDurationLine(for duration: TimeInterval) -> String {
        let totalSeconds = max(1, Int(ceil(duration)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if uiLanguage == .english {
            if minutes == 0 {
                return "\(seconds)s"
            }

            if seconds == 0 {
                return "\(minutes)m"
            }

            return "\(minutes)m \(seconds)s"
        }

        if minutes == 0 {
            return "\(seconds) 秒"
        }

        if seconds == 0 {
            return "\(minutes) 分钟"
        }

        return "\(minutes) 分 \(seconds) 秒"
    }

    func localizedFutureDurationDescription(_ interval: TimeInterval) -> String {
        let totalMinutes = max(1, Int(ceil(interval / 60)))

        if uiLanguage == .english {
            guard totalMinutes >= 60 else {
                return totalMinutes == 1 ? "1 minute" : "\(totalMinutes) minutes"
            }

            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60

            if minutes == 0 {
                return hours == 1 ? "1 hour" : "\(hours) hours"
            }

            return "\(hours) hours \(minutes) minutes"
        }

        guard totalMinutes >= 60 else {
            return "\(totalMinutes) 分钟"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if minutes == 0 {
            return "\(hours) 小时"
        }

        return "\(hours) 小时 \(minutes) 分钟"
    }

    // MARK: Reminder schedule lead time

    func localizedLeadTimeDescription(triggerAt: Date, meetingStartAt: Date) -> String {
        localizedDurationLine(for: max(1, meetingStartAt.timeIntervalSince(triggerAt)))
    }

    func localizedScheduledReminderLine(for context: ScheduledReminderContext) -> String {
        let leadTime = localizedLeadTimeDescription(triggerAt: context.triggerAt, meetingStartAt: context.meeting.startAt)

        if context.triggeredImmediately {
            return localized(
                "距离会议已经太近，因此会立即开始提醒，倒计时持续 \(context.countdownSeconds) 秒。",
                "The meeting is too close, so the reminder starts immediately and the countdown lasts \(context.countdownSeconds) seconds."
            )
        }

        return localized(
            "将在会议开始前 \(leadTime) 触发提醒，倒计时持续 \(context.countdownSeconds) 秒。",
            "The reminder will trigger \(leadTime) before the meeting and the countdown lasts \(context.countdownSeconds) seconds."
        )
    }

    // MARK: Effective countdown

    /// 当前倒计时秒数会同时影响 Overview 展示、提醒页文案和音频页说明。
    var effectiveCountdownSeconds: Int {
        if let overrideSeconds = reminderPreferencesController.reminderPreferences.countdownOverrideSeconds, overrideSeconds > 0 {
            return overrideSeconds
        }

        if let selectedSoundProfile = soundProfileLibraryController.selectedSoundProfile {
            return max(1, Int(ceil(selectedSoundProfile.duration)))
        }

        return 1
    }

    var effectiveCountdownDurationLine: String {
        localizedDurationLine(for: TimeInterval(effectiveCountdownSeconds))
    }
}
