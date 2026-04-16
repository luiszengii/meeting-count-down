# AGENTS.md

## 模块名称

`scripts`

## 模块目的

这个目录用于存放仓库级自动化脚本，当前主要负责本地开发、`Release` 构建导出和手动分发辅助动作。它负责把重复命令收敛成可复用入口，但不负责替代 Xcode 工程本身的构建配置。

## 包含内容

- 本地 `Release` 构建与导出脚本。
- GitHub Release 创建与上传辅助脚本。
- GitHub Release workflow 所需 secrets 的导出与写入辅助脚本。
- 未来如果需要，也可以继续放不依赖付费签名链路的辅助脚本，例如清理构建产物、生成手动分发包、打印当前版本信息。

## 关键依赖

- `zsh` / `bash`
- `xcodebuild`
- 当前仓库里的 [project.yml](../project.yml) 与 [MeetingCountdown.xcodeproj](../MeetingCountdown.xcodeproj)
- macOS 自带的 `ditto`、`find`、`cp`、`rm` 等命令行工具

## 关键状态 / 数据流

当前脚本的数据流应尽量保持简单：从仓库根目录读取工程元数据，调用 `xcodebuild` 产出 `Release` app，再把产物复制到仓库内的临时输出目录并打成 zip / dmg。当前默认会同时导出 `universal` 和 `arm64` 两套手动分发资产，但脚本不应保存长期状态，也不应把签名、账号凭证或用户个人配置写入仓库。

## 阅读入口

先读 [export-release.sh](./export-release.sh)、[release-gh.sh](./release-gh.sh) 和 [configure-release-secrets.sh](./configure-release-secrets.sh)。如果后续这里新增更多脚本，优先看文件头注释和参数约定，再看具体实现。

## 开发注意事项

- 这个目录下的脚本默认使用 ASCII，注释使用中文，说明脚本目的、输入参数、失败语义和为什么这样设计。
- 新脚本应默认使用保守失败策略，例如 `set -euo pipefail`，避免构建失败后继续打包旧产物。
- 不要把 Apple 开发者账号、签名证书、notarization 凭证或其他敏感信息硬编码进脚本。
- 当前阶段的脚本应围绕“无会员手动分发”设计，不要偷偷把正式签名发布链路重新耦合进来。
