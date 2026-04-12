# 手动安装与首次打开放行说明

这份文档面向当前 `Phase 6` 的小范围测试用户。当前安装包仍然是“未 notarize”的手动分发版本，所以安装体验不会像 App Store 或 `Developer ID` 签名应用那样顺滑。目标不是掩盖这件事，而是先把“怎样最快跑通”讲清楚，再把 signed / unsigned 的边界和维护者导出方式放到后面。

## 最快安装路径

如果你只是想最快确认这个 app 能不能装上、能不能读到飞书日历，请先走这 5 步：

1. 拿到 `.app`、`.zip` 或 `.dmg` 后，先把文件放到本机磁盘里，不要直接在浏览器下载列表或聊天工具预览器里打开。
2. 如果拿到的是 `.zip`，先解压；如果拿到的是 `.dmg`，先把里面的 `FeishuMeetingCountdown.app` 拖到 `Applications`。
3. 在 Finder 里找到 `Applications/FeishuMeetingCountdown.app`，右键选择“打开”，再在系统弹窗里继续点“打开”。
4. 打开飞书 `设置 -> 日历 -> CalDAV 同步 -> 进入设置`，复制用户名、专用密码和服务器地址。
5. 打开 macOS 自带“日历”应用，进入 `设置 -> 账户 -> + -> 其他 CalDAV 账户 -> 手动`，粘贴飞书提供的配置；回到 app，授权访问日历并勾选同步出来的飞书日历。

## 完成后你应该看到什么

如果安装和接入成功，通常会依次出现这些结果：

1. `FeishuMeetingCountdown.app` 可以从 `Applications` 正常打开。
2. 第一次授权时，系统会弹出 Calendar 访问权限请求，或者 app 会提示你去系统设置修复权限。
3. 设置页里能看到一个或多个同步出来的系统日历候选项。
4. 你勾选目标飞书日历后，菜单栏会显示“下一场会议”倒计时，或者显示“当前暂无可提醒会议”。

## 先判断你的测试目标

- 如果你只是想验证“用户能不能拖进 `Applications`、能不能通过 Gatekeeper 首次打开”，默认 unsigned 包就够了。
- 如果你要在另一台 macOS 机器上验证“app 是否真的能读取 Calendar / EventKit 数据”，不要只发 unsigned 包。请先用稳定签名身份导出 signed 包，再交给测试用户。

原因很简单：对跨设备系统权限来说，“能打开 app”和“系统愿意把 Calendar 权限稳定绑定给这个 app”不是同一件事。当前仓库已经把这个坑单独记录在 [unsigned DMG 在另一台 Mac 上无法稳定承接 Calendar 权限](./pitfalls/unsigned-dmg-calendar-permission-on-other-mac.md)。

## 安装包形态

当前建议分发这三种形态中的任意一种：

1. `FeishuMeetingCountdown.app`
2. `FeishuMeetingCountdown-<version>-build<build>-<arch>-<signed|unsigned>.zip`
3. `FeishuMeetingCountdown-<version>-build<build>-<arch>-<signed|unsigned>.dmg`

如果你是仓库维护者，可以使用 [scripts/export-release.sh](../scripts/export-release.sh) 和 [scripts/create-dmg.sh](../scripts/create-dmg.sh) 生成这些产物。

## 首次打开方式

macOS 对未签名或未 notarize app 的拦截通常会比普通应用更严格。建议测试用户第一次打开时直接使用下面的方式，而不是普通双击：

1. 在 Finder 里找到 `FeishuMeetingCountdown.app`
2. 右键点击它
3. 选择“打开”
4. 在系统弹窗里再次点击“打开”

如果这一步通过了，后续通常可以直接正常启动。

## 如果系统仍然拦截

在 macOS 14 Sonoma 上，如果你已经尝试过一次打开，但系统提示“无法验证开发者”或阻止启动，可以按下面路径手动放行：

1. 打开“系统设置”
2. 进入“隐私与安全性”
3. 滚动到安全性区域
4. 找到和 `FeishuMeetingCountdown.app` 对应的阻止提示
5. 点击“仍要打开”或等价按钮
6. 返回 Finder，再次右键应用并选择“打开”

如果系统没有出现“仍要打开”的入口，通常是因为你还没有先尝试过一次启动；先执行一次“右键 -> 打开”，再回到“隐私与安全性”页查看。

## 首次启动后的必要步骤

应用成功打开后，还需要继续完成下面这些设置，否则不会读到会议：

1. 在飞书里打开 `设置 -> 日历 -> CalDAV 同步 -> 进入设置`
2. 复制飞书提供的用户名、专用密码和服务器地址
3. 打开 macOS 自带“日历”应用，进入 `设置 -> 账户`
4. 点击左下角 `+`
5. 选择“其他 CalDAV 账户”
6. 账户类型选择“手动”
7. 粘贴飞书提供的用户名、密码、服务器地址
8. 回到 app，授予系统日历读取权限
9. 在 app 里选择同步出来的飞书日历

## 常见限制

- 当前版本不是正式签名版本，首次安装门槛比普通 macOS 软件更高。
- 当前版本没有 notarization，因此不同机器上的 Gatekeeper 提示可能略有差异。
- 当前版本即使通过 `.dmg` 安装，也仍然可能在首次打开时被系统拦截。
- 如果维护者给的是 unsigned 包，它不能可靠用于验证另一台机器上的 Calendar / EventKit 权限；这类测试必须先拿带稳定签名身份的导出包。
- 当前版本没有自动更新；如果后续给出新包，需要用户手动替换旧 app。
- 当前版本读到的是 macOS Calendar 已经同步下来的数据，飞书里的临近改期或取消不一定会立刻反映到 app。

## 仓库维护者如何导出安装包

如果你是仓库维护者，在仓库根目录执行：

```bash
./scripts/export-release.sh
```

如果你要导出一个适合“另一台 macOS 机器上验证 Calendar / EventKit 权限”的测试包，请显式传入稳定签名身份：

```bash
./scripts/export-release.sh --signing-identity "Your Local Code Signing Identity"
```

如果你还没有本地可用的代码签名 identity，先看 [本地自签名 Code Signing 身份用于手动分发](./pitfalls/local-self-signed-code-signing-identity-for-manual-distribution.md)。

如果你希望导出一个更像传统 macOS 安装包的测试版 DMG，可以执行：

```bash
./scripts/create-dmg.sh
```

如果你希望 DMG 里的 app 也带稳定签名身份，可以执行：

```bash
./scripts/create-dmg.sh --signing-identity "Your Local Code Signing Identity"
```

脚本会产出：

- `build/manual-release/FeishuMeetingCountdown.app`
- `build/manual-release/FeishuMeetingCountdown-<version>-build<build>-<arch>-<signed|unsigned>.zip`
- `build/manual-release/FeishuMeetingCountdown-<version>-build<build>-<arch>-<signed|unsigned>.dmg`

如果你希望把当前版本直接发布到 GitHub Release，并把本地生成的 `.zip` / `.dmg` 作为 release assets 上传，可以执行：

```bash
./scripts/release-gh.sh --tag v0.1.0 --signing-identity "Your Local Code Signing Identity"
```

仓库里的 GitHub Actions 也已经支持在推送 `v1.2.3` 这类 tag 时自动执行同样的 release 上传流程；它会要求仓库已配置签名相关 GitHub secrets，并默认校验 tag 版本与 `project.yml` 里的 `MARKETING_VERSION` 一致。

如果你希望直接把当前本机已有的代码签名 identity 写成 GitHub Release workflow 所需的四个 secrets，可以执行：

```bash
./scripts/configure-release-secrets.sh --signing-identity "Your Local Code Signing Identity"
```

这个脚本会在本机导出 `.p12` 并调用 `gh secret set`；如果 macOS 弹出“允许导出私钥”的钥匙串授权框，需要在本机确认一次。

如果只想先确认脚本入口是否正常，可以执行：

```bash
./scripts/export-release.sh --help
```
