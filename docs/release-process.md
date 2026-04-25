# Release 流程教程（维护者视角）

这份文档面向"完全没做过 macOS 应用发版"的维护者，讲清楚本仓库 Release 的全部链路：从 `git push tag` 到用户能下载安装。

读完之后你应该能：

- 独立发一个新版（不需要再问"下一步是什么"）
- 看懂 `release.yml` workflow 每一步在做什么
- 当 release fail 时知道去哪里看日志、怎么排查
- 评估"要不要付 $99 加入 Apple Developer Program"这个长期决策

> 配套阅读：
> - [./manual-installation.md](./manual-installation.md) ——面向**用户**的安装教程（怎么放行未签名 app）
> - [./adrs/2026-04-02-phase-6-manual-distribution-without-paid-membership.md](./adrs/2026-04-02-phase-6-manual-distribution-without-paid-membership.md) ——为什么走"无会员手动分发"路线
> - [../scripts/release-gh.sh](../scripts/release-gh.sh) / [../scripts/export-release.sh](../scripts/export-release.sh) / [../scripts/create-dmg.sh](../scripts/create-dmg.sh) ——Release 各步的真正干活脚本
> - [../.github/workflows/release.yml](../.github/workflows/release.yml) ——CI 编排入口

## 1. 概念铺垫：什么叫 "Release"

写代码 = 一堆 `.swift` 文件，没法直接给别人用。要让别人能用，需要：

1. **构建** (build)：把 `.swift` 编译成 macOS 能直接执行的 `.app`
2. **签名** (codesign)：在 `.app` 上盖一个数字图章，告诉 macOS "这是我做的"
3. **打包** (package)：把 `.app` 装进 `.zip` 或 `.dmg` 方便下载
4. **分发** (distribute)：把打包好的文件挂到一个网址，告诉别人去哪儿下

整套流程做一次 → 产生一个 **Release**（发版）。每个 Release 有一个版本号（`v0.2.0`），用户能挑某一版下载。

GitHub 提供一个叫 [Releases](https://github.com/luiszengii/meeting-count-down/releases) 的页面，就是用来挂这些打包好的文件的。

## 2. 这个项目的特殊约束

正经的 macOS 应用要想"用户双击 .dmg 直接装"，需要两件事：

| | 干什么 | 多少钱 |
|---|---|---|
| **Apple Developer Program 会员** | 拿到一个叫 **Developer ID** 的签名身份 | $99/年 |
| **公证** (Notarization) | 用 Developer ID 签完之后，把 app 上传给 Apple 让它扫一遍恶意代码、回个证书 | API 调用免费，**但前提是有 Developer ID 证书 = 必须先付 $99** |

**当前未加入会员**（参见上面引用的 ADR）。所以这个项目走的是"**手动分发**"路线：

- 用一个**本地自签名身份**（你自己 Mac 上生成的 cert，不是 Apple 颁的）签 app
- 不做公证
- 用户下载后第一次打开会被 macOS 拦：**"无法验证开发者，文件可能损坏"**
- 用户必须**手动**去"系统设置 → 隐私与安全性 → 仍要打开"放行一次

这是这个项目所有"奇怪"安排（不开 Mac App Store、要写 install 文档教用户放行）的根源。

## 3. Tag push 之后到底发生了什么

`git push origin v0.2.0` 触发了一连串自动化。完整链路：

```
你本地                    GitHub                            macos-15 runner               用户
─────                    ──────                           ──────────────                ────
git push v0.2.0    ─────►  收到 tag                ─────►  起一台临时 macOS VM
                          看 .github/workflows/release.yml
                          匹配 on.push.tags='v*.*.*' ✓
                                                          install xcodegen
                                                          xcodegen generate
                                                          导入签名证书 (从 secrets)
                                                          xcodebuild Release build
                                                          codesign 签名
                                                          打包 .zip + .dmg
                                                          gh release create
                                                          上传 .zip + .dmg
                          创建 Releases/v0.2.0  ◄────────  成功
                          (有附件可下载)
                          删除临时 VM (带走 keychain)
                                                                            用户访问 Releases 页 ────►  下载 .dmg
                                                                            双击挂载 .dmg
                                                                            拖 .app 到 Applications
                                                                            首次打开被拦
                                                                            去系统设置点"仍要打开"
                                                                            app 启动
```

整个过程**你只做了 `git push v0.2.0` 一步**，剩下都是 GitHub Actions 自动跑的。典型耗时 3–4 分钟。

## 4. workflow 文件详解 ([`.github/workflows/release.yml`](../.github/workflows/release.yml))

### 触发条件

```yaml
on:
  push:
    tags:
      - "v*.*.*"
```

只有 push 一个形如 `v0.2.0` 的 tag 才触发。`git push v0.2.0` 命中。**普通 commit push（包括 push 到 main）不会触发这个 workflow**——main 分支的 push 走的是 [`tests.yml`](../.github/workflows/tests.yml)（见第 8 节对比）。

### 运行环境

```yaml
runs-on: macos-15
```

GitHub 提供 macOS 虚拟机（每月 2000 分钟开源额度）。每次 workflow 启动一台全新的 VM，跑完销毁。

### Secrets

```yaml
env:
  MACOS_CERTIFICATE_P12_BASE64: ${{ secrets.MACOS_CERTIFICATE_P12_BASE64 }}
  MACOS_CERTIFICATE_PASSWORD:   ${{ secrets.MACOS_CERTIFICATE_PASSWORD }}
  MACOS_SIGNING_IDENTITY:       ${{ secrets.MACOS_SIGNING_IDENTITY }}
  MACOS_KEYCHAIN_PASSWORD:      ${{ secrets.MACOS_KEYCHAIN_PASSWORD }}
```

四个签名相关的敏感数据，存在仓库的 **Settings → Secrets and variables → Actions**（**不在代码里**，只有你和 GitHub 知道）：

| Secret | 是什么 |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | 你的本地自签名证书的 base64 编码（一个加密文件） |
| `MACOS_CERTIFICATE_PASSWORD` | 这个证书文件的解锁密码 |
| `MACOS_SIGNING_IDENTITY` | 证书在 Keychain 里的显示名（如 "Lingjun Zeng"） |
| `MACOS_KEYCHAIN_PASSWORD` | 临时 keychain 的密码（VM 用完就销毁的随机串） |

第一次配置走 [`scripts/configure-release-secrets.sh`](../scripts/configure-release-secrets.sh)。详见 [pitfall: local-self-signed-code-signing-identity-for-manual-distribution](./pitfalls/local-self-signed-code-signing-identity-for-manual-distribution.md)。

### 7 个步骤

#### Step 1: `Checkout Repository`

```yaml
- uses: actions/checkout@v5
  with:
    fetch-depth: 0
```

把代码拉到 VM。`fetch-depth: 0` 是拉**完整 git 历史**（不是浅克隆），因为后面 `release-gh.sh` 会读 git tag 校验。

#### Step 2: `Validate Release Secrets`

```bash
for name in MACOS_CERTIFICATE_P12_BASE64 ...; do
  if [[ -z "${!name:-}" ]]; then exit 1; fi
done
```

**检查 4 个 secret 是否都存在**。漏配了哪个 secret 就在这一步 fail，不会浪费后面时间跑构建。

#### Step 3: `Install XcodeGen`

```bash
brew install xcodegen
```

GitHub macos-15 镜像自带 Homebrew 但不一定有 xcodegen，所以装一下。

#### Step 4: `Regenerate Xcode Project`

```bash
xcodegen generate
```

读 `project.yml` 生成 `MeetingCountdown.xcodeproj`。这一步保证 CI 用的工程文件**完全由 yml 决定**，不依赖你本地有没有最新提交 .xcodeproj。

#### Step 5: `Import Signing Certificate` ⭐ 最复杂

```bash
# 1. 把 secret 里的 base64 解码成 .p12 证书文件
python3 -c "Path(...).write_bytes(base64.b64decode(os.environ['MACOS_CERTIFICATE_P12_BASE64']))"

# 2. 创建一个临时 keychain
security create-keychain -p "$MACOS_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

# 3. 把 .p12 证书导入这个 keychain
security import "$CERTIFICATE_PATH" -k "$KEYCHAIN_PATH" -P "$MACOS_CERTIFICATE_PASSWORD" ...

# 4. 让 codesign 命令能用这个 keychain
security set-key-partition-list ...
security default-keychain -d user -s "$KEYCHAIN_PATH"
```

为什么这么麻烦？因为 macOS 的 `codesign` 必须从 **Keychain** 读签名证书。CI 上的 VM 是空的，所以要现场建一个临时 keychain、把证书塞进去、告诉系统"用这个 keychain"。Step 7 会销毁。

#### Step 6: `Create Or Update Release` ⭐ 真正干活

```bash
./scripts/release-gh.sh --tag "$GITHUB_REF_NAME" --signing-identity "$MACOS_SIGNING_IDENTITY"
```

`release-gh.sh` 内部又调了两个脚本：

```
release-gh.sh
├── 校验 git 工作区干净、tag 格式 v X.Y.Z、project.yml 版本号匹配 tag
├── 调 export-release.sh
│     ├── xcodebuild Release configuration build (universal + arm64 两个 arch)
│     ├── codesign 签名 .app
│     └── 打 .zip
├── 调 create-dmg.sh
│     └── 把 .app 装进 .dmg 磁盘镜像
└── 调 gh release create v0.2.0 ...
      └── 上传 .zip 和 .dmg 作为 Release 附件
```

`gh` 是 GitHub 官方命令行工具，从 CI 直接创建 GitHub Release（不需要你手点网页）。

#### Step 7: `Cleanup Temporary Keychain`

```yaml
if: always()
run: |
  security delete-keychain "$KEYCHAIN_PATH"
```

`if: always()` 表示**不管前面成功失败都跑**。销毁临时 keychain。其实 VM 用完就销毁，keychain 也没了，但显式删一下是安全卫生。

## 5. 用户视角

用户去 [Releases 页](https://github.com/luiszengii/meeting-count-down/releases)看到一个版本，附件大致是：

- `FeishuMeetingCountdown-vX.Y.Z-buildN-universal.dmg` (Intel + Apple Silicon 都能跑)
- `FeishuMeetingCountdown-vX.Y.Z-buildN-arm64.dmg` (Apple Silicon 包，更小)
- `FeishuMeetingCountdown-vX.Y.Z-buildN-universal.zip`
- `FeishuMeetingCountdown-vX.Y.Z-buildN-arm64.zip`

用户操作：
1. 下载 `.dmg`
2. 双击挂载 → 看到 `FeishuMeetingCountdown.app`
3. 拖到 `应用程序` 文件夹
4. 双击 → macOS 弹窗 **"无法打开'FeishuMeetingCountdown'，因为无法验证开发者"** ❌
5. 去 系统设置 → 隐私与安全性 → 滚到底 → 看到一行 "已阻止 FeishuMeetingCountdown" → 点 **"仍要打开"**
6. 再次双击 app → 第二次弹窗 **"打开吗？"** → 确认 → app 启动 ✓

之后每次打开都正常，不再被拦。整套放行流程已经写在 [`docs/manual-installation.md`](./manual-installation.md) 里给用户看。

## 6. 你以后要做的事（核心 how-to）

每次发新版只需要：

```bash
# 1. 改版本号
vim project.yml          # MARKETING_VERSION: 0.2.1

# 2. 重新生成 Xcode 工程让版本号同步进 .pbxproj
xcodegen generate

# 3. commit 这次改动
git add project.yml MeetingCountdown.xcodeproj/project.pbxproj
git commit -m "Bump version to 0.2.1"
git push origin main

# 4. 打 tag 触发 release
git tag v0.2.1
git push origin v0.2.1   # ← 这一步触发整个 release workflow
```

3 分多钟后 Release 自动出现在 GitHub。

### 版本号怎么选

按 [Semantic Versioning](https://semver.org) 的语义（`MAJOR.MINOR.PATCH`）：

| 改的位 | 叫法 | 用于 |
|---|---|---|
| `0.2.0 → 0.2.1` | **patch bump** | 纯 bug 修复，无新功能、无破坏性 |
| `0.2.0 → 0.3.0` | **minor bump** | 加了新功能 / 重构，但向后兼容 |
| `0.2.0 → 1.0.0` | **major bump** | 破坏性变更（旧用户数据要迁移、API 不兼容） |

判断时看 dev-logs 里这个 release 累积了什么——如果有架构重构、新依赖、新模块，跳 minor；如果只是 bug fix，跳 patch。

## 7. 什么会让 release fail

按可能性从高到低：

| 失败点 | 表现 | 怎么修 |
|---|---|---|
| `project.yml` 版本号和 tag 不匹配 | release-gh.sh 校验阶段 fail | 确保 `MARKETING_VERSION` 和 tag 数字一致（`0.2.1` ↔ `v0.2.1`）|
| 4 个 secret 任一缺失 | Step 2 fail | 重新跑 [`scripts/configure-release-secrets.sh`](../scripts/configure-release-secrets.sh) |
| 你本地的签名证书过期 | codesign step fail | 重新生成本地自签名 cert（非 Apple Developer ID 的话不会过期但 macOS 升级可能让它失效） |
| 代码 build 不过 | xcodebuild fail | 修代码再打 tag。**注意 CI 用 Swift 6.0 比本地严**，见 [pitfall: swift-version-divergence-local-vs-ci](./pitfalls/swift-version-divergence-local-vs-ci.md) |
| 已经存在同名 Release | gh release create 报 already exists | 删掉同名 Release（`gh release delete v0.2.1`）或加 `--clobber` 覆盖 |

### 排查 fail 的步骤

```bash
# 1. 看哪一步 fail
gh run list --workflow=release.yml --limit=3

# 2. 看具体的 error log
gh run view <RUN_ID> --log-failed | tail -50
```

## 8. 与 tests.yml workflow 的区别

项目有两个 workflow：

| | `tests.yml` | `release.yml` |
|---|---|---|
| 何时跑 | 每次 push 到任何分支 + 每次 PR | 只有 push tag `v*.*.*` |
| 干什么 | xcodebuild build + 单元测试 + SwiftLint | 加上签名 + 打包 + 上传 GitHub Release |
| 用 secrets | 不用任何 secret | 用 4 个签名 secret |
| 跑多久 | ~1m30s | ~3m30s |
| 失败影响 | 你看到红❌但 main 还能合 | tag 不会自动删，但 release 没生成 |

策略：**先看 `tests.yml` 绿了再 push tag** 触发 release，避免发出去的 release 是带 build 错误的版本（虽然 release.yml 也会重新 build，但 tests.yml 上 fail 而 release.yml 上过的 case 罕见）。

## 9. 关于公证 / 升级到 ADP 的判断

如果哪天觉得"用户首次装要去设置点放行"太烦，想升级到"用户双击直接装"，路径如下。

### 完整的签名 + 公证链路

```
普通签名证书（自己生成的，不要钱）
    └─ 不能公证 → 用户首次打开必须手动放行 (你现在的状态)

Developer ID 证书（必须付 $99/年的 ADP 会员费）
    └─ 可以公证 (公证 API 调用本身免费)
        └─ macOS 自动信任 → 用户双击直接打开 ✓
```

### 你能选的几条路

| 路线 | 钱 | 用户体验 | 适合谁 |
|---|---|---|---|
| **现状（自签 + 手动放行）** | 0 | 首次安装要去设置点"仍要打开" | 朋友、技术圈、自用、beta tester |
| **加入 Apple Developer Program** | $99/年 | 双击直接装，无任何警告 | 非技术用户、想公开分发 |
| **Mac App Store** | $99/年 + 应用审核 | 商店搜得到，自动更新 | 想要曝光、愿意被审核约束 |

### 一些可能省钱的角落

- ADP 不区分个人/公司价格，都是 $99/年
- **学生**：苹果 [Apple Developer App](https://developer.apple.com/programs/students/) 教育计划，部分学校学生可申请免费 ADP（要在白名单学校）
- **非营利**：[Apple's Fee Waiver Program](https://developer.apple.com/support/membership-fee-waiver/) 给认证非盈利组织免费
- 没有"试用 30 天"或"免费一年"这种官方福利

### 决策信号

| 信号 | 倾向付费 | 倾向继续手动放行 |
|---|---|---|
| 月活用户超过 100 个非技术人 | ✅ | |
| 用户里有人因为不会放行就放弃了 | ✅ | |
| 想做自动更新（Sparkle 也最好有 Developer ID 才能让用户信任） | ✅ | |
| 主要给自己 / 几个朋友 / 同事用 | | ✅ |
| 项目还在小规模迭代不确定要不要长期维护 | | ✅ |
| 你已经有 ADP 用于别的项目（一个会员可以签所有 app） | ✅ | |

### 升级后改动量

代码改动**很小**，主要：

1. 注册 ADP，拿到 Developer ID 证书
2. 把 [`scripts/export-release.sh`](../scripts/export-release.sh) 里的签名身份从你本地自签换成 Developer ID
3. 加一步 `xcrun notarytool submit ... --wait`（公证 API 调用）
4. 加一步 `xcrun stapler staple` (把公证票据钉到 .app 上，让没网络的用户也能验证)
5. 改 [`release.yml`](../.github/workflows/release.yml) 加这两步
6. secret 多一个 notarization 凭证

需要时再单独写 ADR 推翻 [2026-04-02 phase-6-manual-distribution-without-paid-membership](./adrs/2026-04-02-phase-6-manual-distribution-without-paid-membership.md)。

## 10. TLDR

**Release = "把代码变成用户能下的安装包"。这个项目的 release 是一个 macOS GitHub Actions workflow，由 push `v*.*.*` 形式的 tag 触发，跑完产出 .zip / .dmg 挂到 GitHub Releases 页面给人下载。因为没付 Apple Developer 会员费，用户首次打开要手动放行。每次发版自己只做四步：改 `project.yml` 版本号 → xcodegen → commit → 打 tag 推。**
