# reminder-engine-reconcile-cancels-ongoing-playback

## 现象

连续创建若干场间隔在 `2 ~ 5` 分钟的会议后，只有最后一场会议成功播放了提醒音频；前面的会议虽然能在弹层里看到倒计时归零，但到点时没有任何声音。单元测试完全通过，菜单栏和弹层的显示也看起来正常。

## 背景

问题出现在 [ReminderEngine.swift](../../MeetingCountdownApp/ReminderEngine/ReminderEngine.swift) 的 reconcile 路径上。提醒引擎通过 `Publishers.sink` 订阅 `SourceCoordinator.$state`，只要上游任一字段变化就会走一次 `reconcile(with:)`。而 `SourceCoordinator.refresh(trigger:)` 在一次刷新里会多次修改 `@Published` 的 `SourceCoordinatorState` 字段（`isRefreshing`、`lastRefreshAt`、`nextMeeting`、`meetings`、`lastErrorMessage`……），再叠加 `EKEventStoreChanged` 通知触发的额外刷新，相当于在一次用户可感知的动作里向提醒引擎推送多次"同一场下一场会议"的 reconcile。

## 排查过程

1. 先怀疑 `AppRefreshController` 的刷新节奏把"上一场"会议挤掉了，但读代码发现 `NextMeetingSelector` 只会过滤掉 `startAt < now` 的会议，播放中的会议完全符合下一场条件，不应该被挤走。
2. 再怀疑 `SpyReminderAudioEngine` 测试和生产路径不一致，但比对后确认 `SelectableSoundProfileReminderAudioEngine` 的 `AVAudioPlayer` 播放路径没有问题；真机重放同一首音频也没问题，只是在密集会议场景下被提前停。
3. 把 [ReminderEngine.swift](../../MeetingCountdownApp/ReminderEngine/ReminderEngine.swift) 的 `reconcile(with:)` 改成详细日志跟踪后，发现会议 A（`10:00`）在 `09:59:50` 左右进入 `.playing` 之后，下一次 reconcile（由 refresh 周期或 `EKEventStoreChanged` 引起）会命中 `cancelOutstandingWork(shouldStopAudio: true)`，直接把正在 `AVAudioPlayer.play()` 的实例停掉。后续 B、C、D 会议重复同一幕，只有队尾的那场因为之后不再发生 nextMeeting 变化才侥幸播完。
4. 回看 `canReuseCurrentState(for:executionPolicy:)` 发现它原本用结构 `==` 比较整个 `ScheduledReminderContext`，包含了 `triggeredImmediately: Bool` 字段。
5. 重新按时间轴推演：在调度的那一刻 `triggerAt > now` → `triggeredImmediately == false`；状态机切到 `.playing` 后，`AVAudioPlayer` 开始播放；此时若 reconcile 再被触发，新算出的 `triggerAt` 仍然等于原值（未过期），但 `now` 已经越过 `triggerAt`，于是 `triggeredImmediately` 被重算成 `true`。两个 context 其它字段完全相同，只有这个派生布尔值不同，结构 `==` 判为不等 → 走取消分支。

## 根因

`ScheduledReminderContext.triggeredImmediately` 本质是"调度决定"的瞬时派生值，只用于告诉 `reconcile` 是走 `scheduler.schedule(after:)` 还是直接 `triggerReminder`。它不是提醒身份的一部分：同一条提醒在"会前调度 → 进入播放 → 触发时刻之后"这几个子阶段里，这个值会自然翻转。把它放进结构 `Equatable` 并让 `canReuseCurrentState` 直接比较整条 context，就让"身份判定"耦合上了"派生阶段"，从而在播放中被误判成"新提醒"，触发 cancel 路径。

## 解决方案

在 [ReminderEngine.swift](../../MeetingCountdownApp/ReminderEngine/ReminderEngine.swift) 里把 `canReuseCurrentState(for:executionPolicy:)` 的比较字段显式收缩到真正属于提醒身份的子集：`meeting`、`triggerAt`、`countdownSeconds` 和当前 `activeExecutionPolicy`。`triggeredImmediately` 不再参与这项判断，函数头用中文注释锁定"为什么不能让它进来"，避免以后有人回填误操作。`ScheduledReminderContext` 的结构 `Equatable` 保持不变，继续在日志、`lastTriggeredIdentity` 比较等路径里正常工作，因为那些路径要的正是"值相等"，而不是"身份相等"。

## 预防方式

- `ReminderEngine` 后续任何 reconcile 相关改动，都要回看 `canReuseCurrentState` 的字段集：新增字段前先回答"这个字段在 `.playing` 状态下会不会随 `now` 变化"，只要会，就不能进入复用相等性。
- 如果给 `ScheduledReminderContext` 新增派生字段，优先放到 engine 本地变量而不是 context 结构里；确需进入 context，就在该字段旁用中文注释说明它"参不参与身份判定"。
- 为"播放中 reconcile 再触发"补一条回归测试：触发 `.playing` 后再推同一 `SourceCoordinatorState`，断言 `audioEngine.stopCallCount` 没有增加、`scheduler.activeTasks` 只保留 playback completion 那一条。这条测试能直接锁住本 pitfall 描述的 race。
- 真机排查"只有最后一场响铃"、"密集会议只有一次提醒"这类现象时，优先怀疑 reconcile 路径的取消副作用，而不是调度延迟或会议源本身。

## 相关链接

- 开发日志：[2026-04-22](../dev-logs/2026-04-22.md)
- ADR：[2026-04-22 menu-bar-presentation-ownership](../adrs/2026-04-22-menu-bar-presentation-ownership.md)
- 相关目录 `AGENTS.md`：[ReminderEngine](../../MeetingCountdownApp/ReminderEngine/AGENTS.md)
