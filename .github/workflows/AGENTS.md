# AGENTS.md

## 模块名称

`.github/workflows`

## 模块目的

这个目录用于存放 GitHub Actions 工作流，当前重点是 Git tag 触发的 Release 自动发布链路。它负责定义“什么时候触发、用哪些 secrets、调用哪个脚本、向 GitHub 上传什么产物”，但不负责直接实现 `.app` / `.zip` / `.dmg` 的具体打包细节。

## 包含内容

- Release 自动发布 workflow。
- 未来如果需要，也可以继续放测试、文档检查或其他 GitHub 平台自动化流程。

## 关键依赖

- 仓库根目录的 [project.yml](../../project.yml) 和 [scripts](../../scripts/AGENTS.md)。
- macOS GitHub Actions runner。
- 仓库级 GitHub secrets（仅在 release.yml 中使用）：
  - `MACOS_CERTIFICATE_P12_BASE64`：base64 编码的 .p12 签名证书
  - `MACOS_CERTIFICATE_PASSWORD`：.p12 证书密码
  - `MACOS_SIGNING_IDENTITY`：codesign 用的 identity 名称
  - `MACOS_KEYCHAIN_PASSWORD`：CI 临时 keychain 密码
- 新增 secret 必须同步更新本文件、release.yml 的校验 step、以及对应 ADR。
- tests.yml 不允许引用任何 secret，保持纯净的 PR 校验通道。

## 关键状态 / 数据流

这里的关键状态流应保持清晰：收到 `vX.Y.Z` tag 后，先校验版本，再导入签名证书，随后调用本地脚本构建 signed 产物，最后创建或更新同名 GitHub Release。workflow 只应编排步骤和传递参数，不应私自演化出另一套独立打包规则。

## 阅读入口

先读 [release.yml](./release.yml)。如果后续新增别的 workflow，也先看文件头部步骤命名和 secrets 约定，再看具体命令。

## 开发注意事项

- 每个 workflow 都要把触发条件、所需 secrets 和失败语义写清楚，避免维护者只能靠 Actions 日志猜行为。
- Release 相关 workflow 需要显式声明 `contents: write`，否则 `gh release` 上传资产会失败。
- 只要 workflow 与签名、版本号或 Release 产物规则有关，就要确保它和本地脚本保持完全一致，不要让 CI 和本地分别维护两套版本/命名逻辑。
