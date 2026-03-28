# AGENTS.md

## 项目名称
Feishu Meeting Countdown for macOS

当前路线为 `BYO Feishu App` 模式，即每个用户自己创建并配置飞书应用，macOS 客户端在本地完成 OAuth、Token 刷新、日历拉取、倒计时调度和音效播放。

## 项目概览
这是一个面向 macOS 的菜单栏常驻应用。应用读取用户飞书账号中的会议日历，在会议开始前自动触发倒计时和音效播放。

本项目采用“用户自配飞书应用 + 本地客户端直连飞书 API”的模式。软件本体可以公开分发，每个用户在自己的飞书租户内完成应用配置和授权。

当前版本聚焦 macOS 与飞书会议场景。

## 当前定位

### 当前接入模式
- 每个用户自己创建 **企业自建应用**。
- 客户端本地保存用户自己应用的 `App ID`、`App Secret`、`user_access_token`、`refresh_token`。
- 客户端直接调用飞书 OAuth 接口和 Calendar API。

### 适用用户
- 具备飞书开放平台使用能力的技术用户。
- 可以自行创建飞书企业自建应用的企业管理员、IT、开发者或高级用户。
- 可以接受一次性完成应用权限、重定向 URL、凭证配置的用户。

## 项目目的

### 用户价值
- 在会议开始前提供比飞书原生通知更强的提醒。
- 用可定制的音效和倒计时方式，将“进入会议状态”的动作前置。
- 让提醒逻辑与飞书会议数据自动联动，不需要用户手动设闹钟。

### 产品目标
- 做成可安装、可分享的独立 macOS 软件。
- 通过 `BYO Feishu App` 方式，让用户可以在自己的飞书租户范围内独立完成接入。
- 首版只聚焦“读取会议 + 准确提醒 + 可稳定使用”。

## 飞书接入方案

### 推荐应用类型
- `企业自建应用`

### 必需权限
- 在飞书开发者后台开启 **用户身份权限**
- `calendar:calendar:readonly`
- `offline_access`

### 必需安全配置
- 在应用 **安全设置** 中配置固定重定向 URL：
  - `http://127.0.0.1:23388/oauth/callback`

### 说明
- 客户端启动授权流程时，会在本地启动固定端口的 loopback HTTP 回调监听。
- 浏览器授权完成后，飞书会重定向到本地回调地址。
- 客户端收到 `code` 后，直接在本地使用 `App ID + App Secret` 换取 `user_access_token`。

## 用户自配置内容

用户在首次接入时需要完成以下配置：

- 创建飞书 **企业自建应用**
- 为应用开启并发布 **用户身份权限**：
  - `calendar:calendar:readonly`
  - `offline_access`
- 在 **安全设置** 中添加重定向 URL：
  - `http://127.0.0.1:23388/oauth/callback`
- 将应用的 `App ID` 和 `App Secret` 输入到 macOS 客户端
- 在客户端内发起授权并完成首次登录

## 核心功能

### V1 必做功能
- 首次启动配置向导：
  - 填写 `App ID`
  - 填写 `App Secret`
  - 检查本地回调端口是否可用
  - 校验飞书配置是否基本正确
- 飞书账号连接与断开
- 本地 OAuth 授权
- 本地获取 `user_access_token`
- 通过 `offline_access` 获取 `refresh_token`
- 本地刷新 `user_access_token`
- 读取用户主日历或用户选择的目标日历
- 获取“下一场即将开始的会议”
- 菜单栏展示当前状态：
  - 未配置应用
  - 已配置但未授权
  - 已授权但暂无会议
  - 下一场会议信息
  - 倒计时中
- 手动立即刷新日历数据
- 定时拉取最新日历数据
- 睡眠唤醒后立即刷新
- 网络恢复后立即刷新
- 用户可导入本地音效文件
- 自动读取音效时长，并将音效时长映射为倒计时秒数
- 在会议开始前按照音效时长触发播放
- 支持测试播放音效
- 支持静音模式和总开关
- 支持开机启动
- 支持点击提醒后打开飞书会议链接或对应会议详情

### V1.1 建议功能
- 多套音效方案切换
- 指定日历生效
- 跳过全天事件
- 跳过已取消事件
- 仅对有视频会议信息的事件生效
- 仅对“已接受”或“未拒绝”的会议生效
- 支持会议前系统通知
- 支持会议开始后自动停止倒计时态
- 支持在设置页检测飞书应用配置是否缺权限、缺发布、缺 redirect URL

### 当前范围
- macOS 菜单栏常驻应用
- 飞书 Calendar API 接入
- 用户自配置飞书应用
- 本地 OAuth、本地刷新、本地定时同步
- 本地音效播放与会议前倒计时

## 功能定义细则

### 倒计时规则
- 倒计时秒数默认等于当前音效文件时长，向上取整到秒。
- 如果用户手动设置倒计时秒数，则优先使用手动值。
- 如果音效时长大于会议剩余时间，则：
  - 默认立即触发播放；
  - 同时在 UI 中提示“音效长于剩余会议时间”。
- 如果会议在短时间内被修改或取消，需实时重新计算或取消任务。

### 会议识别规则
- 默认取“当前时间之后最近的一场非全天会议”。
- 首版以飞书日历事件开始时间为准。
- 循环日程按展开后的实例处理，不直接对抽象规则本体处理提醒。

### 音效规则
- 支持格式：`mp3`、`m4a`、`aac`、`wav`
- 音效文件保存在用户本地应用目录
- 音效播放使用系统默认输出设备
- 首版聚焦本地音效文件导入与播放

### 刷新规则
- 启动应用后立即拉取一次日历数据
- 用户点击“立即刷新”后立刻重拉
- 正常空闲状态下每 `120` 秒轮询一次
- 当下一场会议开始时间小于 `30` 分钟时，刷新频率提升到每 `30` 秒一次
- 系统睡眠唤醒、网络恢复、时区变化、手动修改配置后立即重新同步
- 当 `sync_token` 失效或增量同步失败时，自动回退到一次全量同步

## 技术栈

### macOS 客户端
- 语言：Swift 5.10+ / Swift 6
- UI：SwiftUI
- 菜单栏：`MenuBarExtra`，必要时使用 AppKit 的 `NSStatusItem`
- 音频播放：AVFoundation / `AVAudioPlayer`
- 本地通知：UserNotifications
- 安全存储：Keychain
- 本地持久化：UserDefaults + 文件系统
- 启动项：ServiceManagement
- 网络：`URLSession`
- 本地 OAuth 回调监听：固定端口 loopback HTTP 服务
- 系统事件监听：网络状态、睡眠唤醒、时区变化

### 飞书接入
- OAuth 授权码模式
- `user_access_token`
- `refresh_token`
- Calendar API

## 架构

### 总体架构
- macOS 客户端负责：
  - 飞书应用配置
  - 本地 OAuth 回调
  - Token 交换
  - Token 刷新
  - 日历拉取
  - 本地定时
  - 音效播放
  - 系统集成
- 飞书开放平台负责：
  - 用户授权
  - Token 签发
  - Calendar API 提供
- 产品运行形态为本地客户端直连飞书开放平台。

### 敏感数据存储原则
- 当前模式下，`App Secret` 属于用户自己创建的飞书应用凭证。
- 客户端通过 Keychain 保存：
  - `app_id`
  - `app_secret`
  - `user_access_token`
  - `refresh_token`
  - token 过期时间
- 本地数据库或文件系统只保存：
  - 非敏感偏好设置
  - `sync_token`
  - 已规范化的近期会议缓存
  - 音效配置
  - 提醒偏好

### 本地授权流程
1. 用户在客户端输入 `App ID` 与 `App Secret`。
2. 客户端启动本地 loopback 回调服务：
   - `http://127.0.0.1:23388/oauth/callback`
3. 客户端构造飞书授权链接，并在浏览器中打开。
4. 用户在浏览器中完成飞书授权。
5. 飞书将浏览器重定向到本地回调地址，并附带 `code`。
6. 客户端解析本地回调中的 `code`。
7. 客户端直接调用飞书 `oauth/token` 接口，提交：
   - `grant_type=authorization_code`
   - `client_id`
   - `client_secret`
   - `code`
   - `redirect_uri`
8. 客户端获取 `user_access_token` 与 `refresh_token`。
9. 客户端将凭证写入 Keychain。

### 本地刷新流程
1. 客户端检测 `user_access_token` 即将过期。
2. 客户端直接调用飞书 `oauth/token` 刷新接口，提交：
   - `grant_type=refresh_token`
   - `client_id`
   - `client_secret`
   - `refresh_token`
3. 飞书返回新的 `user_access_token` 与新的 `refresh_token`。
4. 客户端原子替换 Keychain 中的旧 token。

### 日历同步流程
1. 客户端启动后读取本地凭证与偏好设置。
2. 如果 token 过期或即将过期，则先刷新 token。
3. 获取日历列表并选择目标日历。
4. 对目标日历执行首次全量同步。
5. 保存 `sync_token`。
6. 后续固定间隔执行增量同步。
7. 每次同步后重新计算“下一场需要提醒的会议”与本地 timer。

### 数据拉取策略
- 首选增量同步
- 增量同步失败时自动全量重建
- 日程查询窗口建议覆盖：
  - 当前时间前 `30` 分钟
  - 当前时间后 `24` 小时
- 若用户未来需要跨天密集日程支持，可扩展为 `48` 小时窗口

### 倒计时调度策略
- 客户端永远只维护一个“下一场会议”的本地调度任务。
- 一旦下一场会议变化，立即取消旧任务并重新注册新任务。
- 睡眠唤醒、时区变化、网络恢复后立即重算。
- 当 token 刷新失败或拉取失败时，菜单栏状态切换为异常态，并提供重试入口。

## 模块划分

### macOS 客户端模块
- `AppShell`
  - 应用入口
  - 菜单栏与设置窗口
- `FeishuAppConfigModule`
  - 用户输入 `App ID`
  - 用户输入 `App Secret`
  - 校验 redirect URL 与权限前置条件
- `OAuthLoopbackServer`
  - 本地回环 HTTP 监听
  - 接收飞书 OAuth 回调
  - 解析 `code`
- `AuthModule`
  - 发起授权
  - Token 交换
  - Keychain token 管理
- `FeishuAPIClient`
  - 日历列表
  - 主日历信息
  - 日程列表
  - 日程详情
- `ScheduleSyncEngine`
  - 全量同步
  - 增量同步
  - 事件标准化
  - `sync_token` 管理
- `ReminderEngine`
  - 下一场会议计算
  - 本地定时
  - 倒计时状态机
- `AudioEngine`
  - 音效导入
  - 时长分析
  - 播放与停止
- `Preferences`
  - 用户偏好
  - 过滤规则
  - 开机启动
  - 刷新频率
- `NotificationModule`
  - 系统通知
- `Diagnostics`
  - 配置校验
  - API 错误提示
  - Token 状态检查

## 数据设计

### Keychain 数据
- `app_id`
- `app_secret`
- `user_access_token`
- `refresh_token`
- `access_token_expires_at`
- `refresh_token_expires_at`

### 本地非敏感数据
- `selected_calendars`
- `sync_token`
- `last_successful_sync_at`
- `recent_events_cache`
- `sound_profiles`
- `reminder_preferences`
- `window_state`

### 客户端本地模型
- `FeishuAppConfig`
  - app id
  - redirect uri
  - scopes
- `AccountSession`
  - user identifier
  - tenant identifier
  - selected calendars
  - token expiry metadata
- `SoundProfile`
  - local file path
  - duration
  - custom countdown seconds
  - volume
- `ReminderPreference`
  - enable sound
  - enable notification
  - filter settings
  - auto launch
  - refresh interval

## 开发计划

### Phase 0：项目初始化
- 创建 macOS 客户端工程
- 建立菜单栏应用骨架
- 建立本地配置模型
- 确定固定 loopback 回调端口

### Phase 1：飞书应用自配置
- 完成 `App ID / App Secret` 输入页
- 完成 Keychain 安全存储
- 完成“检测配置是否完整”逻辑
- 完成本地诊断页：
  - redirect URL 是否匹配
  - 权限是否缺失
  - refresh 是否可用

### Phase 2：本地 OAuth 链路
- 启动本地回调服务
- 构造授权 URL
- 接收本地回调 `code`
- 完成本地 token 兑换
- 完成 refresh token 刷新链路
- 验证用户断开连接逻辑

### Phase 3：飞书日历读取
- 获取主日历信息
- 获取日历列表
- 获取日程列表
- 处理分页、时间窗口、`sync_token`
- 规范化飞书会议模型
- 完成手动刷新
- 完成定时刷新

### Phase 4：本地提醒引擎
- 计算下一场会议
- 建立本地 timer
- 菜单栏状态切换
- 系统通知触发
- 音效播放
- 会议变更后重新调度

### Phase 5：设置与偏好
- 音效导入与删除
- 音效时长自动识别
- 倒计时秒数覆盖配置
- 日历过滤
- 会议过滤
- 开机启动
- 刷新策略配置

### Phase 6：打包与分享
- Universal 构建
- 签名
- notarization
- DMG 打包
- 自动更新方案
- 用户自配置文档

### Phase 7：公开测试
- 内测用户按文档自行创建飞书应用并接入
- 修复权限缺失、redirect 配置错误、refresh 失败等问题
- 修复睡眠、唤醒、网络波动、时区切换问题
- 增加崩溃日志和错误上报

## 测试计划

### 客户端单元测试
- token 过期判断
- refresh 触发条件
- refresh token 原子替换逻辑
- 下一场会议选择逻辑
- 音效时长映射逻辑
- 倒计时调度逻辑
- 会议过滤规则
- `sync_token` 失效后的全量回退逻辑

### 客户端集成测试
- 首次输入 `App ID / App Secret`
- 本地 OAuth 登录闭环
- 登录后首次同步
- 增量同步
- 手动刷新
- 定时刷新
- 会议改期后重新调度
- 会议取消后取消提醒
- 导入音效后自动识别时长

### 客户端系统测试
- 开机启动后是否正常常驻
- 系统睡眠后唤醒是否恢复
- 断网后恢复网络是否重拉数据
- 时区变化后是否重算会议时间
- 本地回调端口被占用时是否给出明确报错
- 浏览器未登录飞书状态下的 OAuth 体验
- 飞书应用权限不完整时是否给出明确指引

### 飞书配置兼容性测试
- 应用未发布时的行为
- 未授予 `calendar:calendar:readonly` 时的报错提示
- 未授予 `offline_access` 时的报错提示
- `redirect_uri` 不匹配时的报错提示
- refresh 开关未开启时的报错提示

### 手工验收场景
- 正常会议前 10 秒播放音效
- 正常会议前 20 秒播放音效
- 会前 5 分钟改期
- 会前 3 秒取消
- 重复日程实例提醒
- 多个连续会议的切换
- 没有会议时的菜单栏状态
- 用户点击“立即刷新”后 3 秒内看到状态更新

## 部署方式

### macOS 客户端支持策略

#### 目标系统版本
- macOS 15 Sequoia：完整支持
- macOS 14 Sonoma：完整支持
- macOS 13 Ventura：基础支持，作为最低目标版本

#### CPU 架构
- Apple Silicon：优先支持
- Intel：建议提供 Universal Binary 支持，避免限制用户安装

#### 分发方式
- 开发阶段：Xcode 本地运行 + unsigned build
- 内测阶段：签名后的 `.app` 或 `.dmg`
- 正式阶段：
  - Developer ID 签名
  - Apple notarization
  - DMG 分发
  - 自动更新建议使用 Sparkle 2

### 运行方式
- 用户安装 macOS 客户端
- 用户在本机输入飞书应用配置
- 客户端在本机完成授权、刷新、同步和提醒

## 工程原则
- 客户端本地闭环优先
- 每个用户的飞书应用配置互相隔离
- 敏感信息只进 Keychain，不进明文文件
- 首版先保证“下一场会议提醒”准确，再扩展更多视觉效果
- 先保证授权、同步、刷新稳定，再做更多产品层包装

## 风险与注意事项
- 当前模式要求用户自己具备飞书开放平台配置能力，使用门槛较高
- 如果用户所在租户没有创建自建应用权限，产品无法完成接入
- `offline_access` 未配置会导致无法长期保持登录
- `refresh_token` 为一次性使用，刷新时必须原子替换
- 本地 loopback 端口可能被其他程序占用，需要检测与提示
- 菜单栏应用在系统睡眠/唤醒后容易出现 timer 漂移，必须主动重算
- 重复日程和例外实例是提醒逻辑最容易出错的部分
- 首次音频播放存在解码延迟，需要预加载
- 签名、notarization、自动更新是面向他人分发时的强依赖，不可后补到最后一周再做

## 首版里程碑定义

### M1：能配置
- 用户能完成 `App ID / App Secret` 配置
- 本地回调地址可用
- 配置错误有可读提示

### M2：能登录
- 用户能授权飞书
- token 能拿到并刷新

### M3：能读会
- 能看到下一场会议
- 能手动刷新
- 能定时拉取会议变化

### M4：能提醒
- 能在正确时机播放音效
- 菜单栏状态正确

### M5：能分发
- 可签名
- 可 notarize
- 可生成 DMG
- 可让其他 macOS 用户安装并自行配置飞书应用

## 当前结论
本项目当前采用“`用户自建飞书企业应用 + macOS 本地客户端直连飞书 OAuth 与 Calendar API + 本地 Keychain 存储 + 本地定时提醒`”的架构进行实现。
