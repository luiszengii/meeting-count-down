# shared-bundle-id-between-debug-and-release-confuses-calendar-permission

## 现象

- 通过 GitHub Release 安装到 `/Applications/FeishuMeetingCountdown.app` 的版本，在设置页里一直显示“待授权”或“尚未决定是否允许访问日历”。
- 同一台机器上，从 Xcode 或本地构建目录直接启动的开发版却可以正常读取 Calendar / EventKit 数据。
- 用户在“系统设置 -> 隐私与安全性 -> 日历”里看起来已经给过权限，但 release 版 app 里 `EKEventStore.authorizationStatus(for: .event)` 仍然返回 `notDetermined`。

## 背景

这个问题出现在 `Phase 6` 手动分发链路已经切到 signed release 之后。仓库当时把“本地开发版”和“面向用户的 release 版”都维持在同一个 bundle identifier：`com.luiszeng.meetingcountdown`。

与此同时，本地开发版和 release 版并不是同一个代码签名主体：

- 本地开发版通常来自 Xcode / DerivedData 或未正式分发的本机构建。
- GitHub Release 里的 `.dmg` / `.zip` 则来自自动发布链路签出的 signed 产物。

在 macOS 的 TCC / EventKit 权限模型里，这种“同 bundle id，不同代码身份”的组合很容易让系统设置里的展示和运行中 app 真正匹配到的授权记录脱节。

## 排查过程

1. 先从 app 日志里确认错误不是“没有选中日历”，而是稳定落在 `尚未决定是否允许访问日历`，说明业务层拿到的是真正的 `notDetermined`。
2. 再检查 `/Applications/FeishuMeetingCountdown.app` 的签名元信息，确认 release app 已经是 signed 产物，而不是旧的 unsigned DMG 场景。
3. 同时对照用户反馈，发现本地开发版即使放在任意路径也能读到日历，说明路径本身不是关键变量。
4. 最后把现象和 TCC 规则对齐后确认：真正冲突的是“开发版”和“release 版”共用同一个 bundle id，却又不是同一个代码身份，导致权限判断看起来像是“同一个 app”，运行时却不一定命中同一条授权记录。

## 根因

根因不是 EventKit API 调错，也不是 release 包重新退回 unsigned，而是：

1. Debug 和 Release 继续共用 `com.luiszeng.meetingcountdown`。
2. 这两个构建在实际运行时并不是同一个代码签名主体。
3. macOS TCC 对 Calendar 权限的判定不只看显示名；当 bundle id 相同但代码身份不同，系统设置里的“看起来已经授权”并不等于当前运行中的那一个 app 真能命中这条授权。

## 解决方案

1. 在 [project.yml](../../project.yml) 里把 Debug 配置改成单独的 bundle identifier：`com.luiszeng.meetingcountdown.dev`。
2. 同时把 Debug 的显示名改成 `Feishu Meeting Countdown Dev`，避免系统设置、权限弹窗和诊断文本里继续把开发版 / release 版混成同一个名字。
3. Release 继续保留 `com.luiszeng.meetingcountdown`，这样用户安装版的权限主体保持稳定，开发者本地调试也不会再污染 release 版的 TCC 状态。

## 预防方式

- 以后只要某个系统权限依赖 TCC，就不要再让“本地开发版”和“面向用户的 release 版”共用同一个 bundle id。
- 如果需要同时保留多个开发渠道，也应继续按渠道拆分 bundle id，而不是只改 app 名称或路径。
- 排查“系统设置里已经授权，但 app 仍显示待授权”时，优先先看当前运行中的 bundle id、签名身份和日志里的原始授权状态，不要只看系统设置截图。

## 相关链接

- 开发日志：[2026-04-13](../dev-logs/2026-04-13.md)
- ADR：[2026-04-02 Phase 6 先转为无会员手动分发](../adrs/2026-04-02-phase-6-manual-distribution-without-paid-membership.md)
- 相关目录 `AGENTS.md`：[MeetingCountdownApp/SystemCalendarBridge](../../MeetingCountdownApp/SystemCalendarBridge/AGENTS.md)
