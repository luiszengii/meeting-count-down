# eventkit-calendar-permission-debugging

## 现象

- 菜单栏 app 启动后日志会先打印 `Refreshing source system-calendar-caldav because appLaunch`。
- 随后可能出现 `Meeting source failed with domain error: 尚未决定是否允许访问日历`。
- 用户明明已经在别的 app 里“授权访问日历”，但本 app 里点击“授权访问日历”看起来仍然没有反应，或者系统权限提示没有按预期出现。

## 背景

问题出现在项目已经收敛为 `CalDAV -> macOS Calendar -> EventKit` 单一路径之后。应用本身不再管理飞书 OAuth，也不保存 CalDAV 密码，只负责读取已经同步到系统日历里的会议，因此系统日历权限链路一旦有任何误解或配置缺失，用户就会直接卡在接入入口。

## 排查过程

1. 先确认 `SourceCoordinator` 的启动日志是正常行为，不代表已经读取成功；它只是说明 app 在启动时按设计触发了首次刷新。
2. 看到 `尚未决定是否允许访问日历` 时，先不要把问题归因到飞书侧授权，因为当前 app 读的是系统日历，不是飞书 app 自己的权限状态。
3. 回查 [SystemCalendarAccess.swift](../../MeetingCountdownApp/SystemCalendarBridge/SystemCalendarAccess.swift)，确认当前代码调用的是 `EKEventStore.requestFullAccessToEvents()`。
4. 再检查工程配置，发现此前缺少 `NSCalendarsFullAccessUsageDescription`，意味着 app 申请的是“完整读取权限”，但 `Info.plist` 里没有对应的 usage description。
5. 同时明确一个容易混淆的事实：用户给“飞书”或“日历”应用的授权，不会自动继承给本菜单栏 app；EventKit 权限是按 bundle 维度单独判定的。

## 根因

这里实际上叠加了两个独立但容易一起出现的问题：

1. EventKit 的日历权限是“每个 app 单独授权”，不是“只要机器上某个日历相关 app 授权过就全局生效”。
2. 项目切到 `requestFullAccessToEvents()` 后，工程里必须提供 `NSCalendarsFullAccessUsageDescription`，否则权限申请链路不完整。

## 解决方案

1. 在 [project.yml](../../project.yml) 里补上 `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription`。
2. 在设置页里继续保留显式的“授权访问日历”入口，并把 `notDetermined`、`denied`、`authorized` 几种状态分别讲清楚。
3. 在用户说明里明确写出：这里申请的是“本 app 访问 macOS 日历”的权限，不是飞书 app 内部权限。

## 预防方式

- 未来只要修改 EventKit 权限申请 API，就必须同步检查对应的 `Info.plist` usage description 是否匹配。
- 看到“已经在别的 app 里授权了，为什么这里还不行”这类反馈时，先优先排查 bundle 级权限，而不是先怀疑 CalDAV 或飞书账号本身。
- 手工回归时至少覆盖三种状态：首次授权、用户拒绝后重新打开系统设置、已有授权时重新检查。

## 相关链接

- 开发日志：[2026-03-31](../dev-logs/2026-03-31.md)
- ADR：[2026-03-31 CalDAV-only 产品范围收敛](../adrs/2026-03-31-caldav-only-product-scope.md)
- 相关目录 `AGENTS.md`：[SystemCalendarBridge](../../MeetingCountdownApp/SystemCalendarBridge/AGENTS.md)
