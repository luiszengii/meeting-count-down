# Feishu Meeting Countdown for macOS

一个面向 macOS 的菜单栏常驻应用，用于读取飞书日历中的即将开始会议，并在会前自动触发倒计时与音效提醒。

当前项目采用 `BYO Feishu App` 模式：每个用户使用自己创建的飞书企业自建应用完成授权，客户端在本地完成 OAuth、Token 刷新、日历同步和提醒调度。

## 当前目标

- 做成可安装、可分享的独立 macOS 软件
- 首版聚焦“读取会议 + 准确提醒 + 可稳定使用”
- 通过本地客户端直连飞书 API，避免引入额外服务端依赖

## 核心能力

- 飞书应用配置：`App ID`、`App Secret`
- 本地 OAuth 授权与 loopback 回调
- `user_access_token` / `refresh_token` 获取与刷新
- 飞书日历读取与同步
- 自动计算下一场会议
- 菜单栏状态展示
- 会前音效播放与倒计时触发
- 手动刷新、定时刷新、睡眠唤醒后重算
- 本地音效导入、播放测试、静音模式、总开关

## 飞书接入要求

推荐使用飞书 `企业自建应用`，并完成以下配置：

- 开启并发布用户身份权限
- 权限包含 `calendar:calendar:readonly`
- 权限包含 `offline_access`
- 在安全设置中配置重定向地址：
  - `http://127.0.0.1:23388/oauth/callback`

## 技术栈

- Swift 5.10+ / Swift 6
- SwiftUI
- `MenuBarExtra` / `NSStatusItem`
- `URLSession`
- `AVFoundation`
- `UserNotifications`
- Keychain
- UserDefaults + 文件系统

## 预期架构

- macOS 客户端负责本地配置、OAuth 回调、Token 管理、日历同步、提醒调度和音效播放
- 飞书开放平台负责用户授权、Token 签发和 Calendar API
- 敏感信息只进入 Keychain，不写入明文文件

## 当前里程碑

- M1：完成应用配置与诊断
- M2：完成飞书登录与 Token 刷新
- M3：完成会议读取与同步
- M4：完成提醒与菜单栏状态联动
- M5：完成签名、打包与分发

## 仓库说明

当前仓库主要包含项目需求与实现规划文档，详细设计见 [AGENTS.md](./AGENTS.md)。
