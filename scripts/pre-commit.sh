#!/usr/bin/env bash
# scripts/pre-commit.sh
#
# 目的：组合所有项目级 pre-commit 检查，作为 .git/hooks/pre-commit 的入口。
#       现在依次跑：
#         1. AGENTS.md 文档治理检查（pre-commit-agents-check.sh）
#         2. SwiftLint 检查（pre-commit-swiftlint.sh）
#
#       任何一步 exit 非 0 都会阻断提交。先做轻量的 AGENTS.md 检查，再做
#       较重的 SwiftLint，让最常见的"新增 doc 漏更 index"问题先于代码 lint
#       报出来，节省调试循环。
#
# 安装方式：bash scripts/install-pre-commit-hook.sh
# 卸载方式：rm .git/hooks/pre-commit

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)

# ── 1. AGENTS.md 文档治理检查 ──────────────────────────────────────────────
if [ -x "${REPO_ROOT}/scripts/pre-commit-agents-check.sh" ]; then
  bash "${REPO_ROOT}/scripts/pre-commit-agents-check.sh"
fi

# ── 2. SwiftLint 检查 ──────────────────────────────────────────────────────
if [ -x "${REPO_ROOT}/scripts/pre-commit-swiftlint.sh" ]; then
  bash "${REPO_ROOT}/scripts/pre-commit-swiftlint.sh"
fi

exit 0
