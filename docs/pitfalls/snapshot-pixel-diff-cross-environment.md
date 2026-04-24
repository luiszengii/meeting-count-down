# snapshot-pixel-diff-cross-environment

## 现象

接入 [`pointfreeco/swift-snapshot-testing`](https://github.com/pointfreeco/swift-snapshot-testing) 后，作者本地 `xcodebuild test` 13 条 snapshot 测试全过、PNG baseline 入库；同一份代码 push 到 CI 上 13 条 snapshot 测试**全部 fail**：

```
testMenuBarErrorStateLight, failed - Snapshot "light" does not match reference.
testAdvancedPageDark, failed - Snapshot "dark" does not match reference.
... × 13
```

代码完全没改，源文件 / 测试文件 / baseline PNG 都是同一个 commit，但 CI 视觉对比就是不通过。

## 背景

snapshot 测试的工作机制：第一次跑录 baseline PNG 入库 → 之后每次跑把当前渲染输出和 baseline 做**像素级对比**。差一个像素就 fail。这套机制对"代码改动导致视觉回退"非常敏感（这正是它的价值），但同时对"代码没改、环境变了"也一样敏感。

跨环境差异来源：

- **字体渲染**：macOS 不同小版本的 SF Pro 微调（hinting、字重渲染）不一致。
- **HiDPI 缩放与 backing scale**：CI runner 的 `NSWindow` backing scale 行为可能与作者机器不同。
- **AppKit / Core Animation 渲染管线版本**：macOS 26 (作者) vs macOS 15 (CI runner) 在 layer compositing、阴影模糊、玻璃材质实现上有非零差异。
- **图像编码确定性**：`NSImage.pngRepresentation` 在不同系统上的字节级输出不保证一致。

## 排查过程

1. **第一反应**：以为 baseline 录错了，重新跑本地确认 baseline PNG 没问题。
2. **下载 CI artifact 对比**：CI 上的 `attachment` 可以拿到失败时的"实际渲染 PNG"和"baseline PNG"，肉眼对比发现两张图视觉上几乎完全一样，只有抗锯齿边缘像素值有微小差异。
3. **确认环境差异**：macos-15 runner（默认 Xcode 16）≠ 作者本地（macOS 26 + Xcode beta）。字体渲染、layer compositing 都有差。
4. **结论**：不是 baseline 错，是 snapshot 测试**天然不适合跨环境运行**。

## 根因

snapshot 测试假设的前提是"环境稳定"——baseline 录制环境与运行环境必须一致。这个前提在以下场景天然成立：

- 单人 / 单机器开发
- CI 是 baseline 录制的唯一权威环境（作者本地只 run 不 record）

不成立的场景就是当前这种：作者本地录、CI 运行。pointfreeco 的 snapshot framework 文档里也明确说明跨平台/跨 OS 版本的渲染差异不是它要解决的问题。

## 解决方案

最务实的取舍（commit `4e8409d`）：**CI 跳过 snapshot 测试**，把 snapshot 定位为"作者本地写代码时的视觉回归保护"。

[tests.yml](../../.github/workflows/tests.yml) 的 `xcodebuild test` 加两个 `-skip-testing` 排除：

```bash
xcodebuild \
  -scheme FeishuMeetingCountdown \
  -destination "platform=macOS" \
  -configuration Debug \
  test \
  -skip-testing:FeishuMeetingCountdownTests/MenuBarContentViewSnapshotTests \
  -skip-testing:FeishuMeetingCountdownTests/SettingsPageSnapshotTests \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

CI 测试规模 106 → 93（跳过 3 个 MenuBar + 10 个 SettingsPage 共 13 个 snapshot test）。本地仍然全跑 106 含 snapshot。

`docs/adrs/2026-04-23-snapshot-testing-framework.md` 同步加了 Followup 段说明这条 CI 边界。

## 预防方式

- **新增任何 snapshot 测试前，先想清楚 baseline 在哪录、谁是权威源**。当前项目是"作者本地为权威"，所以 CI 跳过；如果未来想反过来，需要单独写 ADR + 改 workflow 让 CI 用 `record: true` 模式生成 baseline 然后 artifact 上传。
- **`tests.yml` 的 `-skip-testing` 列表是项目级约定**，新增 snapshot test class 时要同步加进去，否则 CI 又会因为新加的 snapshot test 变红。
- **不要试图用 SwiftLint 或单测覆盖率工具来代替 snapshot 的视觉守护**——它们覆盖的是不同维度。snapshot 是给 SwiftUI 渲染输出兜底的，没有等价替代物。
- **如果哪天真的需要 CI 守视觉**，先评估两条路：
  1. 加 `precision: 0.95, perceptualPrecision: 0.95` 跨平台容差（可能会掩盖真回归）。
  2. CI 是 baseline 唯一录制源，作者本地只 run 不 record，artifact 流程下载到 PR 后人工 review。

## 相关链接

- 开发日志：[2026-04-24](../dev-logs/2026-04-24.md)
- ADR：[2026-04-23 snapshot-testing-framework](../adrs/2026-04-23-snapshot-testing-framework.md)
- 相关目录 `AGENTS.md`：[.github/workflows/AGENTS](../../.github/workflows/AGENTS.md)
