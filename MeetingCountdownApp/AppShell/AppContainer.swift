import Foundation

/// `AppContainer` 是 Phase 0 的依赖装配入口。
/// 这里显式创建统一时钟、下一场会议选择器和默认的 stub 数据源，
/// 目的是让应用一启动就具备完整但可替换的主状态流。
/// 真正的 EventKit、OAuth、CLI、导入等系统能力会在后续阶段替换这些 stub，
/// 但上层 UI 不需要跟着重写。
enum AppContainer {
    /// 构造应用启动后要注入到 UI 的主状态对象。
    /// 这里集中装配依赖，避免上层 SwiftUI 入口直接知道 stub 或真实实现的细节。
    /// 未来如果把某一路接入从 stub 替换成真实能力，优先改这里，而不是改视图层。
    @MainActor
    /// `@MainActor` 说明这个装配函数会在主线程创建要给 SwiftUI 使用的状态对象。
    static func makeSourceCoordinator() -> SourceCoordinator {
        var sources: [ConnectionMode: any MeetingSource] = [:]

        /// 这里先为每一种连接模式都放一个占位源，确保菜单栏和设置页从第一天开始
        /// 就能在“统一的连接模式切换”前提下工作，而不是等真实接入能力全写完后再装配。
        for mode in ConnectionMode.allCases {
            sources[mode] = StubMeetingSource(
                descriptor: MeetingSourceDescriptor(
                    mode: mode,
                    sourceIdentifier: "phase-zero-\(mode.rawValue)",
                    displayName: mode.displayName
                ),
                currentHealthState: .unconfigured(message: "\(mode.displayName) 尚未完成接入"),
                sampleMeetings: []
            )
        }

        /// 默认从 CalDAV 模式起步，符合当前产品定义的首选引导顺序。
        return SourceCoordinator(
            activeMode: .caldavSystemCalendar,
            sources: sources,
            nextMeetingSelector: DefaultNextMeetingSelector(),
            dateProvider: SystemDateProvider(),
            logger: AppLogger(source: "SourceCoordinator"),
            autoRefreshOnStart: true
        )
    }
}
