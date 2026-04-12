# AGENTS.md

## 模块名称

`.github`

## 模块目的

这个目录用于存放仓库级 GitHub 平台配置，当前主要负责 Actions 工作流和与 GitHub Release 相关的自动化入口。它负责把“tag -> 构建 -> Release 上传”这类平台级流程收口到仓库内，但不负责替代本地脚本本身的构建与打包逻辑。

## 包含内容

- GitHub Actions workflow 定义。
- 后续如果需要，也可以继续放与仓库平台行为直接相关的配置文件，例如 issue / pull request 模板或 CODEOWNERS。

## 关键依赖

- GitHub Actions 运行环境。
- 仓库内已有的 `scripts/` 脚本入口。
- GitHub 提供的 `GITHUB_TOKEN` 与仓库级 secrets。

## 关键状态 / 数据流

当前目录内最重要的数据流是：Git tag 触发 workflow，workflow 读取仓库 secrets，导入临时代码签名身份，调用仓库脚本构建产物，再创建或更新 GitHub Release。平台配置不应直接复制构建逻辑，而应尽量复用仓库脚本，避免本地和 CI 的分发链路分叉。

## 阅读入口

先读 [workflows/AGENTS.md](./workflows/AGENTS.md)，再看具体 workflow 文件。

## 开发注意事项

- 任何新增 workflow 前，先确认仓库里是否已经有对应脚本入口，优先复用脚本而不是把复杂构建逻辑直接堆进 YAML。
- 不要把证书、密码、token 或其他敏感值硬编码进 workflow；只通过 GitHub secrets 或 `GITHUB_TOKEN` 传入。
- 如果 workflow 的行为会改变维护者理解成本，记得同步更新 [README.md](../README.md)、[docs/README.md](../docs/README.md) 和开发日志。
