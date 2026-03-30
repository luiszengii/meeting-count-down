import Foundation

/// `StubMeetingSource` 是 Phase 0 使用的占位数据源。
/// 它的价值在于先把“任何数据源都必须实现相同协议”这件事跑通，
/// 让菜单栏壳层、测试和协调层都不依赖真实系统能力。
/// 后续具体接入落地时，可以逐个把这些 stub 替换成真实实现。
struct StubMeetingSource: MeetingSource {
    let descriptor: MeetingSourceDescriptor
    let currentHealthState: SourceHealthState
    let sampleMeetings: [MeetingRecord]

    /// 占位源直接返回预设健康状态，不做额外计算。
    func healthState() async -> SourceHealthState {
        currentHealthState
    }

    /// 占位刷新永远返回固定样本数据，用于把上层状态流和测试先跑通。
    func refresh(trigger: RefreshTrigger, now: Date) async throws -> SourceSyncSnapshot {
        SourceSyncSnapshot(
            source: descriptor,
            meetings: sampleMeetings,
            healthState: currentHealthState,
            refreshedAt: now
        )
    }
}
