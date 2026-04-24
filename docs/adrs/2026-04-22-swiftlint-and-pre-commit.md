# 2026-04-22 引入 SwiftLint 与 pre-commit hook 防止代码风格漂移

- 状态：Accepted
- 日期：2026-04-22
- 关联日志：暂无

## 背景

审计 T-8 指出：当前代码库整体风格较统一，但没有任何自动化机制阻止渐进式漂移。随着重构路线图（T12 及后续任务）持续推进，新增文件和修改往往由不同 session 的 AI 代理完成，没有 lint 守卫的情况下风格一致性只能靠人工 review 维持，代价随仓库规模线性增长。

具体问题：
- 无 SwiftLint 配置，任何文件都可以不受约束地引入 `!` 强制解包、过长函数体、行超宽等代码气味。
- 无 pre-commit hook，开发者（包括 AI 代理）在本地提交前没有自动检查入口。
- CI 只跑编译和单元测试，没有 lint 步骤，风格问题只能在人工 review 中被发现。

## 决策

### 工具选型：SwiftLint

引入 SwiftLint 0.x（Homebrew 最新稳定版），配置文件为仓库根目录的 `.swiftlint.yml`。

**规则选型逻辑**

| 类别 | 具体规则 / 配置 | 理由 |
|---|---|---|
| 关闭 | `trailing_whitespace` | 编辑器自动格式化负责，无需 lint 重复报告 |
| 关闭 | `todo` | 本项目 TODO 注释是有效的开发信号，不强制清除 |
| 开启（warning）| `force_unwrapping`、`force_cast` | 运行时崩溃的高风险写法，至少要可见 |
| 开启 | `implicit_return` | 统一单行闭包 / 计算属性风格 |
| 开启 | `redundant_nil_coalescing` | `?? nil` 是冗余写法，消除 noise |
| 开启 | `sorted_imports` | 降低合并冲突概率 |
| 调整 | `line_length` warning 140 / error 200 | 140 是可读性优选；200 才是真正不可接受 |
| 调整 | `function_body_length` warning 80 / error 200 | 80 行是拆分信号；200 才是错误 |
| 调整 | `type_body_length` warning 400 / error 800 | SwiftUI View 偏长，400 是合理警戒线 |
| 调整 | `cyclomatic_complexity` warning 12 / error 25 | 超过 12 说明分支偏多；25 是明确代码气味 |

只扫描 `MeetingCountdownApp` 和 `MeetingCountdownAppTests`，排除 `build`、`DerivedData`、`.build`、`scripts`、`docs` 等目录。

### pre-commit hook

通过 `scripts/install-pre-commit-hook.sh` 安装（克隆后运行一次，幂等）。hook 主体为 `scripts/pre-commit-swiftlint.sh`，流程：

```
git commit
  └─ pre-commit-swiftlint.sh
       ├─ swiftlint 未安装？→ 打印提示，exit 0（不阻断）
       ├─ 无暂存 Swift 文件？→ exit 0
       ├─ 有 error？→ 打印问题，exit 1（阻断提交）
       └─ 只有 warning？→ 打印提示，exit 0（放行）
```

只检查当前暂存的 Swift 文件（`git diff --cached --name-only --diff-filter=ACM`），不扫描全仓库，保证速度。

### CI 步骤

在 `.github/workflows/tests.yml` 的"Run Unit Tests"步骤之前插入两步：

1. **Install SwiftLint**：检测 swiftlint 是否存在，否则 `brew install swiftlint`。
2. **Run SwiftLint**：执行 `swiftlint lint --quiet`。warning 输出到日志作为 review signal；只有真正的 error 才导致 CI 失败。不传 `--strict`（否则 warning 也会变 error，首次引入会立刻打断所有 PR）。

## 备选方案

### 方案 A：用 swift-format 代替 SwiftLint

没有采用。`swift-format` 侧重格式化（自动修改文件），而本次需要的是 lint（发现问题 + 报告）。`swift-format` 的规则集不如 SwiftLint 可定制，且与 Xcode 集成需要额外工作。SwiftLint 在 Swift 社区拥有更大的生态和更丰富的规则库。

### 方案 B：完全跳过 lint

没有采用。没有守卫机制的情况下，风格漂移会随 session 数量线性积累；一旦积累到一定规模，统一清理的代价远高于早期引入的成本。

## 影响

- 首次运行（本地 hook 或 CI）会输出一批 warning，这是预期行为；warning 不阻断构建，只作为 review signal。
- 安排单独的后续任务清理 baseline warning，不在本批次修改 Swift 源文件（hard constraint）。
- 任何新增 Swift 文件默认纳入 lint 覆盖，无需额外配置。
- 如果 warning 持续增长，未来可以考虑逐步升级到 `--strict` 模式，或添加 `SwiftLint baseline` 文件锁定 baseline。

## 后续动作

1. 安排专项 task，清掉首次 lint 产出的 baseline warning（不在本 task 内处理）。
2. 评估是否在未来某版本升级到 `--strict` 模式，把 warning 也变成构建失败条件。
3. 如有新规则需求（例如针对 SwiftUI 的专项规则），可在 `.swiftlint.yml` 的 `opt_in_rules` 中追加。

## 状态更新（2026-04-24）：扩展为多检查 hook + AGENTS.md 治理校验

baseline 清理已于 2026-04-24 完成（详见 [dev-log 2026-04-24](../dev-logs/2026-04-24.md)）：SwiftLint error 归零，warning ~95 → 2（剩 2 条是真"该拆 page"的 file_length 信号，刻意保留）。

同时，因为发现 AI 代理在过去 8 个 ADR commit 里反复违反了"新增 ADR / dev-log / pitfall 必须同步更新 docs/index.md"这条文档治理规则（详见 [dev-log 2026-04-24](../dev-logs/2026-04-24.md) 末尾的反思），把 pre-commit hook 由"单一 SwiftLint 检查"扩展为"聚合检查"：

- 新增 [`scripts/pre-commit.sh`](../../scripts/pre-commit.sh) 作为入口聚合脚本，依次跑两个独立检查。
- 新增 [`scripts/pre-commit-agents-check.sh`](../../scripts/pre-commit-agents-check.sh) 机械校验三类文档（ADR / dev-log / pitfall）的索引同步。会同时检查文件被 touch 与内容里包含新文件名两层条件，避免"只 touch 不写条目"绕过。
- 原 [`scripts/pre-commit-swiftlint.sh`](../../scripts/pre-commit-swiftlint.sh) 保持单一职责不变，由聚合脚本调用。
- [`scripts/install-pre-commit-hook.sh`](../../scripts/install-pre-commit-hook.sh) 改为安装聚合入口，已运行的用户重新执行一次即可升级。

设计取舍：

- **检查顺序**：AGENTS.md 检查在前、SwiftLint 在后。AGENTS.md 检查跑得快（只 grep staged 列表），常见违规（漏更 index）能立即暴露，节省后续 SwiftLint 调试循环。
- **CI 暂不执行 AGENTS.md 检查**：本地 hook 是第一道关，CI 主要保护"代码能编译能跑测试"。如果未来发现绕过本地 hook 推上来的 PR 仍在违反索引规则，再加 CI 步骤。
- **绕过策略**：保留 `git commit --no-verify` 用于批量历史回填等极少场景；scripts 在违规消息里明确写出这条 escape hatch 与同时跳过 SwiftLint 的副作用。
