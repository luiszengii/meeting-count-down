import Combine
import Foundation

/// `ReminderScheduledTask` 把底层定时任务包装成最小可取消接口。
/// 提醒引擎只需要“创建”和“取消”任务，不需要知道任务具体是 `Task.sleep`、Timer 还是别的实现。
@MainActor
protocol ReminderScheduledTask: AnyObject {
    /// 当前任务是否已经被取消。
    var isCancelled: Bool { get }
    /// 主动取消当前任务。
    func cancel()
}

/// `ReminderScheduling` 负责把“若干秒后执行某个异步动作”抽象成可替换的调度器。
/// 生产环境用真实 `Task.sleep`，测试环境则可以用可手动触发的假调度器。
@MainActor
protocol ReminderScheduling: AnyObject {
    /// 创建一个延迟执行任务，并返回可取消句柄。
    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> any ReminderScheduledTask
}

/// `TaskBackedReminderScheduledTask` 把 Swift Concurrency 的 `Task` 包装成提醒调度句柄。
@MainActor
final class TaskBackedReminderScheduledTask: ReminderScheduledTask {
    /// 真正等待并执行提醒动作的并发任务。
    private let task: Task<Void, Never>

    /// 初始化时直接接收已经构造好的底层任务。
    init(task: Task<Void, Never>) {
        self.task = task
    }

    /// 透传到底层 `Task` 的取消状态。
    var isCancelled: Bool {
        task.isCancelled
    }

    /// 直接取消底层任务。
    func cancel() {
        task.cancel()
    }
}

/// `TaskReminderScheduler` 是生产环境里的真实调度器实现。
/// 它使用 `Task.sleep` 等待到目标时刻，再把动作切回主 actor 执行。
@MainActor
final class TaskReminderScheduler: ReminderScheduling {
    /// 创建并返回一个真实的异步延迟任务。
    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> any ReminderScheduledTask {
        let task = Task {
            do {
                if delay > 0 {
                    try await Task.sleep(for: .seconds(delay))
                }

                if Task.isCancelled {
                    return
                }

                await operation()
            } catch {
                /// `Task.sleep` 被取消时会抛错；提醒引擎本身已经知道任务被取消，所以这里直接吞掉。
            }
        }

        return TaskBackedReminderScheduledTask(task: task)
    }
}

/// `ReminderEngine` 是 Phase 4 本地提醒闭环的主状态机。
/// 它只围绕“当前下一场会议”维护一条活动提醒，不负责读取日历或决定哪场会才是下一场。
@MainActor
final class ReminderEngine: ObservableObject {
    /// 会议真正开始后，菜单栏标题提醒额外保留多久再回到普通状态。
    /// 这样用户才能真正看到当前会议标题，而不是在倒计时归零瞬间立刻被空闲态覆盖。
    private static let meetingStartedBannerHoldDuration: TimeInterval = 3

    /// 对外暴露的提醒状态，供菜单栏和设置页直接读取。
    @Published private(set) var state: ReminderState

    /// 当前提醒偏好的持久化读取入口。
    private let preferencesStore: any PreferencesStore
    /// 默认音效播放实现。
    private let audioEngine: any ReminderAudioEngine
    /// 当前默认输出设备探测入口。
    private let audioOutputRouteProvider: any AudioOutputRouteProviding
    /// 可替换的延迟调度器。
    private let scheduler: any ReminderScheduling
    /// 统一时钟入口，便于测试固定当前时间。
    private let dateProvider: any DateProviding
    /// 结构化日志入口。
    private let logger: AppLogger

    /// 监听 `SourceCoordinator` 聚合状态变化的订阅。
    private var sourceStateCancellable: AnyCancellable?
    /// 当前真正等待命中提醒的任务。
    private var scheduledReminderTask: (any ReminderScheduledTask)? {
        didSet {
            // 只在任务从 nil → 非 nil（新建任务）时设为 true；
            // 取消或清空时置为 false，确保 deinit 断言不误判。
            _hasActiveScheduledTask = scheduledReminderTask != nil
        }
    }

    /// `deinit` 是 `nonisolated` 的，无法直接访问 `@MainActor` 隔离属性。
    /// 这里保留一个 `nonisolated(unsafe)` 的布尔镜像，仅用于 `deinit` 里的断言检查。
    /// 注意：`cancelOutstandingWork` 会把 `scheduledReminderTask` 置 nil，
    /// 从而把这个标志复位，因此正常取消路径不会触发断言。
    nonisolated(unsafe) private var _hasActiveScheduledTask: Bool = false
    /// 提醒命中后，用于把“正在播放”收回空闲态的后置任务。
    private var playbackCompletionTask: (any ReminderScheduledTask)?
    /// 最近一次已经真正触发过的提醒主键，用来防止同一会议被重复提醒。
    private var lastTriggeredIdentity: ReminderIdentity?
    /// 当前活动提醒调度所绑定的执行策略。
    /// 只要静音或耳机输出策略发生变化，即使会议上下文没变，也应该重建调度。
    private var activeExecutionPolicy: ReminderExecutionPolicy?

    /// 捕捉提醒引擎在还有活跃（未通过 cancel 清空）调度任务时就被销毁的生命周期 bug。
    /// 生产环境下 `assertionFailure` 不会崩溃，但 Debug / 测试构建会及时暴露问题。
    nonisolated deinit {
        if _hasActiveScheduledTask {
            assertionFailure(
                "ReminderEngine deallocated with an outstanding scheduledReminderTask — call stopAll() before releasing"
            )
        }
    }

    /// 先构造一个空闲提醒引擎，后续再通过 `bind` 接上真正的数据源状态流。
    init(
        preferencesStore: any PreferencesStore,
        audioEngine: any ReminderAudioEngine,
        audioOutputRouteProvider: any AudioOutputRouteProviding,
        scheduler: any ReminderScheduling,
        dateProvider: any DateProviding,
        logger: AppLogger
    ) {
        self.preferencesStore = preferencesStore
        self.audioEngine = audioEngine
        self.audioOutputRouteProvider = audioOutputRouteProvider
        self.scheduler = scheduler
        self.dateProvider = dateProvider
        self.logger = logger
        self.state = .idle(message: "当前没有活动提醒任务。")
    }


    /// 把提醒引擎绑定到统一会议状态流上。
    /// 一旦 `SourceCoordinatorState` 变化，这里就会进入统一重算入口，并按需复用或重建提醒任务。
    func bind(to sourceCoordinator: SourceCoordinator) {
        sourceStateCancellable?.cancel()

        sourceStateCancellable = sourceCoordinator.$state.sink { [weak self] sourceState in
            Task { @MainActor [weak self] in
                await self?.reconcile(with: sourceState)
            }
        }
    }

    /// 显式停止所有活动提醒、播放和订阅。
    /// 这个入口主要留给 app 生命周期或未来切换模式时复用。
    func stopAll() async {
        sourceStateCancellable?.cancel()
        sourceStateCancellable = nil
        await cancelOutstandingWork(shouldStopAudio: true)
        state = .idle(message: "当前没有活动提醒任务。")
    }

    /// 这是提醒层的唯一重算入口。
    /// 每次会议列表、权限状态或日历选择变化后，都应该最终走到这里来重建提醒。
    func reconcile(with sourceState: SourceCoordinatorState) async {
        let reminderPreferences = await preferencesStore.loadReminderPreferences()

        guard reminderPreferences.globalReminderEnabled else {
            await cancelOutstandingWork(shouldStopAudio: true)
            state = .disabled
            logger.info("Reminder scheduling skipped because reminders are disabled")
            return
        }

        guard let nextMeeting = sourceState.nextMeeting else {
            await cancelOutstandingWork(shouldStopAudio: true)
            state = .idle(message: idleMessage(for: sourceState))
            return
        }

        do {
            let soundDuration = try await audioEngine.defaultSoundDuration()
            let countdownSeconds = resolveCountdownSeconds(
                from: reminderPreferences,
                defaultSoundDuration: soundDuration
            )
            let executionPolicy = ReminderExecutionPolicy(
                isMuted: reminderPreferences.isMuted,
                playSoundOnlyWhenHeadphonesConnected: reminderPreferences.playSoundOnlyWhenHeadphonesConnected
            )
            let triggerAt = nextMeeting.startAt.addingTimeInterval(-TimeInterval(countdownSeconds))
            let triggeredImmediately = triggerAt <= dateProvider.now()
            let context = ScheduledReminderContext(
                meeting: nextMeeting,
                triggerAt: triggerAt,
                countdownSeconds: countdownSeconds,
                triggeredImmediately: triggeredImmediately
            )

            if canReuseCurrentState(for: context, executionPolicy: executionPolicy) {
                return
            }

            if context.identity == lastTriggeredIdentity {
                await cancelOutstandingWork(shouldStopAudio: true)
                state = .idle(message: "《\(nextMeeting.title)》的提醒已触发，等待下一场会议。")
                return
            }

            await cancelOutstandingWork(shouldStopAudio: true)

            if triggeredImmediately {
                await triggerReminder(
                    context: context,
                    soundDuration: soundDuration,
                    executionPolicy: executionPolicy
                )
                return
            }

            state = .scheduled(context)
            activeExecutionPolicy = executionPolicy
            let delay = max(0, triggerAt.timeIntervalSince(dateProvider.now()))

            scheduledReminderTask = scheduler.schedule(after: delay) { [weak self] in
                guard let self else {
                    return
                }

                await self.triggerReminder(
                    context: context,
                    soundDuration: soundDuration,
                    executionPolicy: executionPolicy
                )
            }

            logger.info(
                "Reminder scheduled for \(nextMeeting.id) at \(triggerAt.formatted(date: .omitted, time: .standard))"
            )
        } catch {
            await cancelOutstandingWork(shouldStopAudio: true)
            state = .failed(message: "准备提醒失败：\(error.localizedDescription)")
            logger.error("Reminder scheduling failed: \(error.localizedDescription)")
        }
    }

    /// 根据偏好和默认音效时长，决定当前应该使用的倒计时秒数。
    /// 手动覆盖值只有在大于零时才生效，避免无效值把提醒提前时间算成零或负数。
    private func resolveCountdownSeconds(
        from reminderPreferences: ReminderPreferences,
        defaultSoundDuration: TimeInterval
    ) -> Int {
        if let overrideSeconds = reminderPreferences.countdownOverrideSeconds, overrideSeconds > 0 {
            return overrideSeconds
        }

        return max(1, Int(ceil(defaultSoundDuration)))
    }

    /// 当上游状态只是重复发布同一场会议时，这里直接复用当前提醒状态，
    /// 避免先取消再重建导致日志噪音、任务抖动，甚至打断已经开始的播放。
    ///
    /// 判断"是否同一条提醒"时故意忽略 `triggeredImmediately`：
    /// 这个标志只记录"调度时是否来不及等完整倒计时"，在提醒已经进入
    /// `.playing` / `.triggeredSilently` 之后，下一次 reconcile 因为 `now` 已经
    /// 越过 `triggerAt`，会把新算出的 context.triggeredImmediately 翻成 true，
    /// 如果参与相等性比较就会被误判成"不同的提醒"并取消正在播放的音频。
    private func canReuseCurrentState(
        for context: ScheduledReminderContext,
        executionPolicy: ReminderExecutionPolicy
    ) -> Bool {
        switch state {
        case let .scheduled(currentContext),
             let .playing(currentContext, _),
             let .triggeredSilently(currentContext, _, _):
            return currentContext.meeting == context.meeting
                && currentContext.triggerAt == context.triggerAt
                && currentContext.countdownSeconds == context.countdownSeconds
                && activeExecutionPolicy == executionPolicy
        case .idle, .disabled, .failed:
            return false
        }
    }

    /// 真正命中提醒时统一走这里，确保“播放”“静音命中”“去重”和日志都在同一条路径里。
    private func triggerReminder(
        context: ScheduledReminderContext,
        soundDuration: TimeInterval,
        executionPolicy: ReminderExecutionPolicy
    ) async {
        lastTriggeredIdentity = context.identity
        scheduledReminderTask = nil
        activeExecutionPolicy = executionPolicy

        if let silentReason = silentTriggerReason(for: executionPolicy) {
            let triggeredAt = dateProvider.now()
            state = .triggeredSilently(context: context, triggeredAt: triggeredAt, reason: silentReason)
            logger.info("Reminder hit silently for \(context.meeting.id)")
            return
        }

        do {
            let startedAt = dateProvider.now()
            state = .playing(context: context, startedAt: startedAt)
            try await audioEngine.playDefaultSound()
            schedulePlaybackCompletion(for: context, after: soundDuration)
            logger.info("Reminder audio started for \(context.meeting.id)")
        } catch {
            state = .failed(message: "播放提醒音效失败：\(error.localizedDescription)")
            logger.error("Reminder audio failed: \(error.localizedDescription)")
        }
    }

    /// 在默认音效播放完成后，把状态从“正在播放”收回“已触发，等待下一场会议”。
    private func schedulePlaybackCompletion(for context: ScheduledReminderContext, after soundDuration: TimeInterval) {
        let countdownAndBannerDelay =
            max(0, context.meeting.startAt.timeIntervalSince(dateProvider.now()))
            + Self.meetingStartedBannerHoldDuration
        let completionDelay = max(max(0, soundDuration), countdownAndBannerDelay)

        playbackCompletionTask = scheduler.schedule(after: completionDelay) { [weak self] in
            guard let self else {
                return
            }

            await self.completePlaybackIfNeeded(for: context)
        }
    }

    /// 只有当当前状态仍然对应同一条播放中的提醒时，才允许收回到空闲态。
    /// 这样可以防止旧任务在会议已改期后又把新状态覆盖掉。
    private func completePlaybackIfNeeded(for context: ScheduledReminderContext) async {
        playbackCompletionTask = nil

        guard case let .playing(currentContext, _) = state, currentContext.identity == context.identity else {
            return
        }

        activeExecutionPolicy = nil
        state = .idle(message: "《\(context.meeting.title)》的提醒已触发，等待下一场会议。")
    }

    /// 统一取消所有活动任务，并按需停止当前音效播放。
    /// 任何重新调度都应该先走这里，避免旧任务和新任务同时活着。
    private func cancelOutstandingWork(shouldStopAudio: Bool) async {
        scheduledReminderTask?.cancel()
        scheduledReminderTask = nil
        playbackCompletionTask?.cancel()
        playbackCompletionTask = nil
        activeExecutionPolicy = nil

        if shouldStopAudio {
            await audioEngine.stopPlayback()
        }
    }

    /// 当没有下一场会议可安排时，尽量把空闲原因说得具体一些。
    private func idleMessage(for sourceState: SourceCoordinatorState) -> String {
        if let lastErrorMessage = sourceState.lastErrorMessage {
            return "当前未建立提醒：\(lastErrorMessage)"
        }

        if case let .unconfigured(message) = sourceState.healthState {
            return "当前未建立提醒：\(message)"
        }

        return "当前没有可安排提醒的下一场会议。"
    }

    /// 按当前执行策略判断这次提醒是否应该静默命中。
    private func silentTriggerReason(for executionPolicy: ReminderExecutionPolicy) -> SilentTriggerReason? {
        if executionPolicy.isMuted {
            return .userMuted
        }

        guard executionPolicy.playSoundOnlyWhenHeadphonesConnected else {
            return nil
        }

        let currentRoute = audioOutputRouteProvider.currentRoute()

        switch currentRoute.kind {
        case .privateListening:
            return nil
        case .speakerLike, .unknown:
            return .outputRoutePolicy(routeName: currentRoute.name)
        }
    }
}

/// `ReminderExecutionPolicy` 把一次提醒真正执行时依赖的偏好收拢成纯值。
/// 这样提醒引擎在判断“能否复用当前调度”时，就不会遗漏静音或耳机策略变化。
private struct ReminderExecutionPolicy: Equatable, Sendable {
    let isMuted: Bool
    let playSoundOnlyWhenHeadphonesConnected: Bool
}
