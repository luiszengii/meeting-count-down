# Feishu Meeting Countdown for macOS

一个面向 macOS 的菜单栏常驻应用，用于读取飞书日历中的即将开始会议，并在会前自动触发倒计时与音效提醒。

当前项目已经收敛为单一路线：`CalDAV -> macOS Calendar -> 本地 app`。用户先把飞书日历通过 CalDAV 同步到 macOS 自带“日历”应用，再由本 app 通过 `EventKit` 只读系统日历并完成提醒。不再提供 `BYO Feishu App`、`离线导入`、`lark-cli` 等其他会议接入方式。

项目同时采用“文档先行”原则：仓库级规则在 [AGENTS.md](./AGENTS.md)，持续演进文档在 [docs/README.md](./docs/README.md)。

## 当前目标

- 做成可安装、可分享的独立 macOS 软件
- 首版只聚焦一条普通用户可走通的 CalDAV 路径
- 先把“能读下一场会议 + 能稳定提醒”做扎实，再扩展更多体验细节

## 核心能力

- 飞书 CalDAV 同步到 macOS Calendar 后的系统日历读取
- 自动计算下一场会议
- 菜单栏状态展示与高优先级提醒态
- 会前音效播放与倒计时触发
- 手动刷新、定时重读、睡眠唤醒后重算
- 本地音效多次导入、列表维护、切换当前提醒音频、播放测试、静音模式、总开关，以及默认关闭的可选“仅在连接耳机时播放倒计时音频”策略
- 菜单栏在倒计时阶段显示秒级剩余时间；最后 `10` 秒进入红色闪烁提醒；会议真正开始后只短暂显示会议标题本身

## 唯一接入路径

### `CalDAV -> macOS Calendar`

- 这是当前唯一支持的飞书会议接入方式
- 用户不需要创建飞书开放平台应用
- app 不保存飞书账号密码，也不管理 OAuth token
- app 只读取已经同步到 macOS Calendar 的飞书会议

推荐按下面步骤操作：

1. 在飞书里进入“设置 -> 日历 -> CalDAV 同步 -> 进入设置”。
2. 复制飞书提供的 `用户名`、`专用密码`、`服务器地址`。
3. 打开 macOS 自带“日历”应用，进入“设置”。
4. 打开“账户”标签页，点击左下角 `+`。
5. 选择“其他 CalDAV 账户”。
6. 账户类型选择“手动”。
7. 把刚刚复制的 `用户名`、`密码`、`服务器地址` 粘贴进去并完成添加。
8. 添加成功后，账户列表里应出现类似 `caldav.feishu.cn` 的供应商。
9. 你可以在 macOS 日历里把刷新间隔调成 `5 分钟` 或更短，尽量缩短系统日历同步延迟。
10. 回到本 app，授予系统日历读取权限，并选择同步出来的飞书日历。

这条路径的限制也要提前说明：app 读到的是 macOS Calendar 当前已经同步下来的数据，所以飞书会议刚被改期或取消时，是否立刻反映出来仍取决于系统日历同步时机。

## 技术栈

- Swift 5.10+ / Swift 6
- SwiftUI
- `NSStatusItem` + `NSPopover`
- `EventKit`
- `AVFoundation`
- UserDefaults + 文件系统

## 当前工程状态

- 原生 macOS 工程已落地，入口工程为 [MeetingCountdown.xcodeproj](./MeetingCountdown.xcodeproj)
- 工程规格文件为 [project.yml](./project.yml)，用于生成并维护原生 Xcode 工程
- App 源码根目录为 [MeetingCountdownApp](./MeetingCountdownApp)
- 单元测试根目录为 [MeetingCountdownAppTests](./MeetingCountdownAppTests)
- 当前文档路线已经切换为 CalDAV-only，后续代码实现也应继续向单一路线收敛
- 本地提醒引擎已经接入运行时：会根据“下一场会议”建立单条活动提醒，并把提醒状态展示到菜单栏和设置页
- Phase 5 的提醒偏好与运行策略已接入运行时，包括总开关、静音、倒计时秒数覆盖、提醒音频多选上传与列表切换、默认关闭的“仅耳机输出时播放”可选项、菜单栏秒级倒计时与最后 `10` 秒红色闪烁、会议开始后的标题提醒、会议过滤、开机启动、`120s / 30s` 刷新策略和同步新鲜度提示
- 菜单栏入口现已切到 `NSStatusItem + NSPopover`，避免 `MenuBarExtra` 标签宿主吞掉倒计时阶段的红色胶囊背景

## 预期架构

- macOS 客户端负责首次引导、系统日历权限申请、目标日历选择、会议读取、提醒调度和音效播放
- macOS Calendar 负责保存 CalDAV 账户并执行远端同步
- 飞书日历提供 CalDAV 同步源
- app 不保存飞书开放平台凭证，不引入自建应用 OAuth 流程

## 当前里程碑

- M1：完成 CalDAV 接入引导与系统日历权限检查
- M2：完成系统日历读取与下一场会议选择
- M3：完成提醒与菜单栏状态联动，本地音效提醒与状态机已落地
- M4：完成签名、打包与分发

## 仓库说明

当前仓库同时包含原生 macOS 工程骨架、实现规划与文档治理规则：

- 工程规格见 [project.yml](./project.yml)
- 原生 Xcode 工程见 [MeetingCountdown.xcodeproj](./MeetingCountdown.xcodeproj)
- App 源码入口见 [MeetingCountdownApp](./MeetingCountdownApp)
- 单元测试入口见 [MeetingCountdownAppTests](./MeetingCountdownAppTests)
- 仓库级规则见 [AGENTS.md](./AGENTS.md)
- 文档系统入口见 [docs/README.md](./docs/README.md)
