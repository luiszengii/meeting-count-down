# AGENTS.md

## 模块名称

`Domain`

## 模块目的

负责定义“无论系统日历原始事件长什么样都必须遵守”的统一业务模型和规则。这里不负责 UI、持久化细节和系统框架桥接。

## 包含内容

- 统一会议模型
- 数据源协议和同步快照
- 下一场会议选择规则
- 刷新触发来源
- 统一时间提供协议

## 关键依赖

- Foundation

## 关键状态 / 数据流

所有上游事件都必须先把原始事件转换成 `MeetingRecord`。随后由 `NextMeetingSelecting` 根据统一规则挑选下一场会议，`SourceCoordinator` 再把结果聚合到菜单栏状态。

## 阅读入口

先看 `MeetingSource.swift` 和 `MeetingRecord.swift`，再看 `NextMeetingSelector.swift`。

## 开发注意事项

- 这里的字段和命名要尽量稳定，避免桥接层每次扩展都改一次公共接口。
- 不要在领域层直接耦合 EventKit 的原始模型。
- 这里的 Swift 文件默认要求学习导向的中文注释：函数级注释、关键计算属性注释、关键字段注释都应主动补齐，默认读者是不熟悉 Swift 的人。
