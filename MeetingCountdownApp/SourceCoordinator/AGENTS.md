# AGENTS.md

## 模块名称

`SourceCoordinator`

## 模块目的

负责把“活动数据源的选择”和“统一会议状态的聚合”收敛到一个地方。它不关心具体接入细节，只认 `MeetingSource` 协议和统一会议模型。

## 包含内容

- `SourceCoordinator.swift`：主状态对象、刷新入口、切换活动源。
- `StubMeetingSource.swift`：Phase 0 使用的占位数据源。

## 关键依赖

- `Domain/`
- SwiftUI / Combine 的可观察对象机制

## 关键状态 / 数据流

`SourceCoordinator` 持有当前活动 `ConnectionMode`，通过对应的 `MeetingSource` 刷新会议列表，再把下一场会议、健康状态、刷新时间和错误信息聚合成 `SourceCoordinatorState` 供 UI 读取。

## 阅读入口

先看 `SourceCoordinator.swift`，再看 `StubMeetingSource.swift`。

## 开发注意事项

- 切换活动数据源时必须重建聚合状态，不能沿用旧源的会议缓存。
- 这里是未来睡眠唤醒、网络恢复、时区变化等系统事件汇入的主入口，不要把这些逻辑散落到各个 View。
- 这里的状态对象、计算属性、刷新入口和错误路径默认都应写中文函数级注释，因为它是整个 app 当前最核心的状态机。
