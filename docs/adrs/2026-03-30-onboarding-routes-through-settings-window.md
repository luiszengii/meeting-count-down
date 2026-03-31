# 2026-03-30 onboarding routes through settings window

- 状态：Accepted
- 日期：2026-03-30
- 关联日志：[2026-03-30 开发日志](../dev-logs/2026-03-30.md)

## 背景

进入 `Phase 1` 以后，项目第一次需要把“四路接入向导”真正挂到可运行的 UI 上。但这时真实的 EventKit 读取、OAuth、CLI 调用和 `.ics` 导入都还没开始做，如果此时再额外创建一个独立 onboarding window、一次性向导流程或复杂场景切换，工程复杂度会先于真实接入能力膨胀。

同时，Phase 0 已经有可工作的菜单栏窗口和设置窗口，`SourceCoordinator` 也已经固定成“设置页是统一状态入口”的壳层结构。现在更需要的是把推荐规则、诊断结果和失败回退先沉淀成稳定状态流，而不是先扩 UI 场景数量。

## 决策

Phase 1 先把接入向导承载在现有 `Settings` 场景里，不新增独立 onboarding window。

具体约束如下：

1. 设置页顶部展示推荐路线、推荐理由和当前模式的 follow-up 提示。
2. 设置页中部展示四路接入模式的状态卡片，标明“推荐 / 可继续 / 受阻 / 辅助”。
3. 设置页底部展示统一 diagnostics 明细和“重新检查”入口。
4. 菜单栏只做轻量提示增强，不承载完整 onboarding 流程。

## 备选方案

### 1. 立即新增独立 onboarding window

没有采用。原因是当前还没有真实接入步骤可走，单独窗口会先引入额外路由、窗口生命周期和状态同步复杂度，而不会立刻提升用户可完成的事情。

### 2. 继续把设置页维持为 Phase 0 占位，只靠菜单栏提示

没有采用。原因是菜单栏空间太小，无法同时承载推荐、阻塞原因、模式切换和诊断细节；如果继续拖延，后续真实接入模块会缺少稳定壳层。

## 影响

- `AppShell` 需要同时注入 `SourceCoordinator` 和 `OnboardingRouter`。
- `OnboardingRouter` 成为新的聚合状态入口，用于把 `DiagnosticsSnapshot` 转成推荐路线和回退文案。
- `SettingsView` 从“模式切换占位页”升级成“接入向导 + 当前状态总览”。
- 后续 `Phase 2` 到 `Phase 4` 可以在这个壳层上逐步把真实接入步骤补进去，而不必再次重构窗口结构。

## 后续动作

1. 在 `Phase 2` 把 CalDAV / EventKit 的真实权限申请、系统日历枚举和读取接入到当前设置页结构。
2. 在 `Phase 3` 把 BYO Feishu App 的配置表单和 OAuth 流程接进当前设置页。
3. 等某条主接入路径已经具备连续可执行步骤后，再评估是否有必要拆出独立 onboarding flow。
