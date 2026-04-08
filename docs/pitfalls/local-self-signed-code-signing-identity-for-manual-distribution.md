# local-self-signed-code-signing-identity-for-manual-distribution

## 现象

- 仓库已经支持 `./scripts/export-release.sh --signing-identity "<Name>"` 和 `./scripts/create-dmg.sh --signing-identity "<Name>"`，但维护者并不知道这个 identity 应该从哪里来。
- 执行 `security find-identity -v -p codesigning` 时，看不到任何可用身份，或者看到的名称和自己以为的证书名称不一致。
- 结果就是：文档里已经强调“跨设备 Calendar / EventKit 权限测试必须使用稳定签名身份”，但维护者在真正打包时仍然会卡在“没有身份可选”这一步。

## 背景

这个问题出现在 `Phase 6` 的无会员手动分发准备阶段。项目已经确认：如果要在另一台 Mac 上验证 Calendar / EventKit 权限链路，不能继续把完全 unsigned 的包当成可靠测试载体，必须给导出产物补一个稳定的代码签名身份。

仓库侧已经在 [export-release.sh](../../scripts/export-release.sh) 和 [create-dmg.sh](../../scripts/create-dmg.sh) 里提供了 `--signing-identity` 参数，但之前缺少一份“维护者如何在本机准备这个 identity”的正式文档，相关经验只散落在聊天记录里。

## 排查过程

1. 先确认跨设备 Calendar 权限问题已经在 [unsigned DMG 在另一台 Mac 上无法稳定承接 Calendar 权限](./unsigned-dmg-calendar-permission-on-other-mac.md) 中被单独记录，根因不是业务代码，而是分发包缺少稳定身份。
2. 再回到当前分发脚本，确认脚本层已经支持显式传入 `--signing-identity`，因此当前阻塞点不在“脚本不能签名”，而在“维护者不知道 identity 从哪里来、叫什么”。
3. 在维护机上执行 `security find-identity -v -p codesigning`，把系统当前实际可用于代码签名的 identity 列出来。这个命令返回的名字，才是脚本参数里应该传入的名字。
4. 如果命令里没有任何 identity，就需要先在“钥匙串访问”中创建一个本地自签名代码签名证书，再重新执行 `security find-identity -v -p codesigning` 确认证书已经被系统识别。
5. 真正可用于当前阶段的最小路径是：
   - 打开“钥匙串访问”
   - 进入 `Keychain Access -> Certificate Assistant -> Create a Certificate`
   - `Identity Type` 选择 `Self Signed Root`
   - `Certificate Type` 选择 `Code Signing`
   - 如需手动确认参数，可勾选 `Let me override defaults`，其余步骤保持默认继续
6. 创建完成后，再执行一次 `security find-identity -v -p codesigning`。只要输出里出现类似 `"Lingjun Zeng"` 这样的名字，就可以把这个字符串原样传给分发脚本。

## 根因

根因不是脚本缺少签名能力，而是文档系统此前只记录了“为什么必须使用稳定签名身份”，没有继续把“如何准备这个身份”固化为维护者文档。

换句话说，项目之前只补了“策略层结论”，没补“操作层落地步骤”。

## 解决方案

1. 保留当前 `--signing-identity` 的分发脚本入口，不引入新的临时打包分支。
2. 把“如何创建本地自签名代码签名证书、如何用 `security find-identity` 找到可用 identity、如何把它传给导出脚本”正式写进仓库文档。
3. 继续明确边界：本地自签名 identity 的价值，是让一组手动导出的测试包在 macOS 看来具有更稳定的一致身份，足以服务当前阶段的小范围跨设备验证；它不等于 `Developer ID`，也不等于 notarization。

## 预防方式

- 以后只要文档里提到 `--signing-identity`，就应该同时给出这份 pitfall 或等价维护者入口，避免参数存在但没人知道如何准备输入。
- 任何人宣称“已经导出了 signed 包”之前，都先执行一次 `security find-identity -v -p codesigning`，确认本机真的存在目标 identity。
- 文档里持续区分三件事：`能打包`、`有稳定代码身份`、`被 Apple 信任链公开信任`。这三件事不是同一层级。

## 相关链接

- 开发日志：[2026-04-03](../dev-logs/2026-04-03.md)
- 开发日志：[2026-04-08](../dev-logs/2026-04-08.md)
- ADR：[2026-04-02 Phase 6 先转为无会员手动分发](../adrs/2026-04-02-phase-6-manual-distribution-without-paid-membership.md)
- 相关目录 `AGENTS.md`：[scripts](../../scripts/AGENTS.md)
