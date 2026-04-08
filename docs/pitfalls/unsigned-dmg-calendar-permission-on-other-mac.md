# unsigned-dmg-calendar-permission-on-other-mac

## 现象

- 在开发机上通过 Xcode 本地运行时，app 可以正常申请并读取 macOS Calendar / EventKit 数据。
- 把仓库导出的 `.dmg` 发送到另一台 macOS 设备后，用户即使已经在“系统设置 -> 隐私与安全性 -> 日历”里给 app 打开权限，app 仍然读不到日历。
- 用户侧看到的是“明明已经授权了，但 app 还是像没授权一样”，而不是一个稳定复现的 Swift / EventKit 异常栈。

## 背景

这个问题出现在 `Phase 6` 的手动分发验证阶段。项目当时为了绕开付费会员门槛，先落地了 unsigned / ad-hoc `Release` 构建、zip 和 DMG 打包，希望先验证“别的机器能不能安装并使用”。

但是当前产品不是一个纯离线 UI 壳层，它必须读取系统日历，而 macOS 的日历权限又属于 TCC / EventKit 这类依赖 app 身份的系统权限。于是“能打开 app”和“系统愿意把日历权限真正绑定到这个 app 身上”变成了两件不同的事。

## 排查过程

1. 先回查 [SystemCalendarAccess.swift](../../MeetingCountdownApp/SystemCalendarBridge/SystemCalendarAccess.swift)，确认 app 仍然调用 `EKEventStore.requestFullAccessToEvents()`，而不是错误地退回了别的权限 API。
2. 再核对 [project.yml](../../project.yml)，确认 `NSCalendarsFullAccessUsageDescription` 仍然存在，因此这次不是 usage description 缺失导致的权限链路不完整。
3. 然后检查分发脚本 [export-release.sh](../../scripts/export-release.sh) 和 [create-dmg.sh](../../scripts/create-dmg.sh)，发现它们都明确沿用了 `CODE_SIGNING_ALLOWED=NO`、`CODE_SIGNING_REQUIRED=NO` 的 unsigned 路线。
4. 对实际产物执行 `codesign -dv --verbose=4`、`codesign -d -r-` 和 `spctl -a -t exec -vv`，结果出现了三个关键信号：
   - `codesign -dv` 显示 `Signature=adhoc`、`Info.plist=not bound`
   - `codesign -d -r-` 直接报 `code object is not signed at all`
   - `spctl` 报 `source=no usable signature`
5. 这说明当前分发包在 macOS 看来并没有一个可稳定复用的代码签名身份。它或许足够让用户在另一台机器上“手动放行后启动”，但不足以作为一个稳定的 TCC 权限主体去承接 EventKit / Calendar 授权。

## 根因

根因不是 EventKit API 选错，也不是 `Info.plist` 少了 `NSCalendarsFullAccessUsageDescription`，而是：

1. `Phase 6` 当前导出的 `.app` / `.zip` / `.dmg` 默认都没有稳定代码签名身份。
2. 跨设备的 macOS 系统权限，尤其是 Calendar / EventKit 这种 TCC 权限，不应把“unsigned app”当成可靠授权载体。
3. 因此用户在系统设置里看到的授权开关，不足以保证运行中的分发 app 能和那条授权记录稳定匹配。

## 解决方案

1. 保留“无会员手动分发”路线，但不再把“完全 unsigned 的 DMG”当成跨设备权限验证包。
2. 在 [export-release.sh](../../scripts/export-release.sh) 和 [create-dmg.sh](../../scripts/create-dmg.sh) 里增加可选 `--signing-identity` 参数，让维护者在有本地稳定签名身份时，可以对复制后的 `.app` 重新签名，再导出 zip / DMG。
3. 在 [manual-installation.md](../manual-installation.md) 里明确写出：如果测试目标包含“另一台机器上读取 Calendar”，就必须先使用稳定签名身份导出；纯 unsigned 包只适合验证 Gatekeeper 放行和安装包装流程。

## 预防方式

- 以后只要某个 Phase 6 / 7 测试场景涉及 TCC 系统权限，就不能默认拿 unsigned 安装包做结论。
- 任何新的手动分发说明都要把“Gatekeeper 放行”和“系统权限可用”分开描述，避免把它们误当成同一件事。
- 如果将来恢复 `Developer ID` 或 notarization，仍要保留这里的教训：权限问题先看“系统把谁认成 app 身份”，再看业务代码本身。

## 相关链接

- 开发日志：[2026-04-03](../dev-logs/2026-04-03.md)
- ADR：[2026-04-02 Phase 6 先转为无会员手动分发](../adrs/2026-04-02-phase-6-manual-distribution-without-paid-membership.md)
- 相关目录 `AGENTS.md`：[scripts](../../scripts/AGENTS.md)
