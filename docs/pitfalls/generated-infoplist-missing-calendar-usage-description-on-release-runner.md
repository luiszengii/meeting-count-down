# generated-infoplist-missing-calendar-usage-description-on-release-runner

## 现象

- 本地手动构建出来的 app 可以正常申请 Calendar / EventKit 权限。
- GitHub Release 下载下来的 `.dmg` / `.zip` 安装包里，点击“授予日历权限”没有任何反应。
- 在“系统设置 -> 隐私与安全性 -> 日历”里也看不到 `FeishuMeetingCountdown` 对应的权限项。
- 进一步检查安装后的 `Info.plist`，发现其中缺少 `NSCalendarsFullAccessUsageDescription`。

## 背景

这个问题出现在 `v0.1.1` release 验证阶段。项目当时仍依赖 Xcode 的 `GENERATE_INFOPLIST_FILE=YES` 和 `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription` 来生成最终的 app `Info.plist`。

本地开发机和 GitHub Actions runner 使用的 Xcode / SDK 版本不同，导致“本地看起来没问题”并不代表最终 release 资产里真的带上了这条权限说明。

## 排查过程

1. 先根据用户反馈确认：release 版点击授权按钮没有弹框，也没有在系统设置里出现 Calendar 权限项。
2. 再检查 `/Applications/FeishuMeetingCountdown.app/Contents/Info.plist`，发现 `NSCalendarsFullAccessUsageDescription` 不存在。
3. 同时对照本地 `build/manual-release/FeishuMeetingCountdown.app/Contents/Info.plist`，发现本地构建产物反而包含这条 key，说明问题不在业务代码，而在“不同构建环境如何生成最终 plist”。
4. 最后确认根因是：当前 release 链路过于依赖 Xcode 自动生成 `Info.plist`，没有把“权限说明 key 是否真的进入最终产物”作为硬校验。

## 根因

根因不是 EventKit API 调错，而是：

1. app 使用自动生成的 `Info.plist`。
2. `NSCalendarsFullAccessUsageDescription` 只通过 `INFOPLIST_KEY_*` build setting 注入。
3. 在 release runner 的 Xcode / SDK 组合下，最终产物没有稳定保留这条 key。

只要缺了这条说明，macOS 就不会正常走 Calendar 权限申请链路。

## 解决方案

1. 在 [Config/FeishuMeetingCountdown-Info.plist](../../Config/FeishuMeetingCountdown-Info.plist) 里显式维护 app `Info.plist`，不再依赖 release runner 自动生成权限说明字段。
2. 在 [project.yml](../../project.yml) 里把 target 配置切到 `GENERATE_INFOPLIST_FILE=NO` 和显式 `INFOPLIST_FILE`。
3. 在 [scripts/export-release.sh](../../scripts/export-release.sh) 里增加 `NSCalendarsFullAccessUsageDescription` 的硬校验；只要导出的 app 缺这个 key，脚本直接失败，阻止继续生成 zip / dmg 和上传 release。

## 预防方式

- 以后所有和 TCC 权限直接相关的 usage description，都优先放进显式 `Info.plist` 文件，而不是只靠自动生成。
- Release 脚本除了“能 build 成功”，还要继续校验最终 `.app` 里真正存在关键权限说明字段。
- 遇到“按钮点了没反应，系统设置里也没有 app 项”这类权限问题时，优先先看最终安装包的 `Info.plist`，不要只看工程配置。

## 相关链接

- 开发日志：[2026-04-13](../dev-logs/2026-04-13.md)
- ADR：[2026-04-02 Phase 6 先转为无会员手动分发](../adrs/2026-04-02-phase-6-manual-distribution-without-paid-membership.md)
- 相关目录 `AGENTS.md`：[scripts](../../scripts/AGENTS.md)
