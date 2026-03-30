# Feishu Meeting Countdown for macOS

一个面向 macOS 的菜单栏常驻应用，用于读取飞书日历中的即将开始会议，并在会前自动触发倒计时与音效提醒。

当前项目采用“四路接入”模式：`CalDAV -> macOS Calendar`、`BYO Feishu App` 直连、`离线导入`、`lark-cli` 辅助。客户端在本地完成会议数据规范化、倒计时调度和音效提醒，不再假设所有用户都具备飞书开放平台权限。

项目现在同时采用“文档先行”原则：仓库级规则在 [AGENTS.md](./AGENTS.md)，持续演进文档在 [docs/README.md](./docs/README.md)。

## 当前目标

- 做成可安装、可分享的独立 macOS 软件
- 首版聚焦“能接入任一路径 + 能读下一场会议 + 能稳定提醒”
- 在有权限时优先走实时或准实时同步，在无权限时提供可退化的本地导入方案

## 核心能力

- `lark-cli` 辅助接入与诊断
- 飞书应用配置：`App ID`、`App Secret`
- 本地 OAuth 授权与 loopback 回调
- `user_access_token` / `refresh_token` 获取与刷新
- 飞书日历 API 读取与同步
- CalDAV 同步到 macOS Calendar 后的系统日历读取
- `.ics` 或会议快照离线导入
- 自动计算下一场会议
- 菜单栏状态展示
- 会前音效播放与倒计时触发
- 手动刷新、定时刷新、睡眠唤醒后重算
- 本地音效导入、播放测试、静音模式、总开关

## 接入路径

推荐顺序：`CalDAV -> BYO Feishu App -> Offline Import`，`lark-cli` 仅作为辅助工具出现，不作为默认接入路径。

### `CalDAV -> macOS Calendar`

- 用户在飞书日历中生成 Mac 专用密码
- 用户在 macOS Calendar 中添加 `Other CalDAV Account`
- 客户端通过 `EventKit` 读取系统日历中的飞书会议

### `BYO Feishu App` 直连

推荐使用飞书 `企业自建应用`，并完成以下配置：

- 开启并发布用户身份权限
- 权限包含 `calendar:calendar:readonly`
- 权限包含 `offline_access`
- 在安全设置中配置重定向地址：
  - `http://127.0.0.1:23388/oauth/callback`

### `离线导入`

- 支持导入 `.ics`
- 可扩展支持 `lark-cli` 导出的会议快照
- 作为无审批、无开放权限时的最终兜底路径

### `CLI 辅助接入`

- 不内置 `lark-cli`
- 由用户或用户自己的 agent 安装并运行
- 用于诊断、权限探测、辅助导入或开发调试

## 技术栈

- Swift 5.10+ / Swift 6
- SwiftUI
- `MenuBarExtra` / `NSStatusItem`
- `URLSession`
- `AVFoundation`
- `EventKit`
- `UserNotifications`
- Keychain
- UserDefaults + 文件系统

## 当前工程状态

- 原生 macOS 工程已落地，入口工程为 [MeetingCountdown.xcodeproj](./MeetingCountdown.xcodeproj)
- 工程规格文件为 [project.yml](./project.yml)，用于生成并维护原生 Xcode 工程
- App 源码根目录为 [MeetingCountdownApp](./MeetingCountdownApp)
- 单元测试根目录为 [MeetingCountdownAppTests](./MeetingCountdownAppTests)
- 当前已完成 `Phase 0`：菜单栏应用骨架、统一会议域模型、活动数据源协调层、固定 loopback 回调配置和基础测试

## 预期架构

- macOS 客户端负责接入方式选择、本地配置、OAuth 回调、Token 管理、系统日历读取、离线导入、提醒调度和音效播放
- 飞书开放平台负责用户授权、Token 签发和 Calendar API
- 飞书日历客户端能力负责 CalDAV 同步
- 敏感信息只进入 Keychain，不写入明文文件

## 当前里程碑

- M1：完成四路接入向导与诊断
- M2：至少完成一条接入路径
- M3：完成会议读取、导入与同步
- M4：完成提醒与菜单栏状态联动
- M5：完成签名、打包与分发

## 仓库说明

当前仓库同时包含原生 macOS 工程骨架、实现规划与文档治理规则：

- 工程规格见 [project.yml](./project.yml)
- 原生 Xcode 工程见 [MeetingCountdown.xcodeproj](./MeetingCountdown.xcodeproj)
- App 源码入口见 [MeetingCountdownApp](./MeetingCountdownApp)
- 单元测试入口见 [MeetingCountdownAppTests](./MeetingCountdownAppTests)
- 仓库级规则见 [AGENTS.md](./AGENTS.md)
- 文档系统入口见 [docs/README.md](./docs/README.md)
