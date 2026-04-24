#!/usr/bin/env bash
# scripts/install-pre-commit-hook.sh
#
# 目的：把 scripts/pre-commit.sh 复制到 .git/hooks/pre-commit，使其在每次
#       git commit 前依次跑：
#         1. AGENTS.md 文档治理检查（pre-commit-agents-check.sh）
#         2. SwiftLint 检查（pre-commit-swiftlint.sh）
#
# 幂等：重复运行会覆盖旧 hook，不会报错。
#
# 使用方式：
#   bash scripts/install-pre-commit-hook.sh
#
# 卸载方式：
#   rm .git/hooks/pre-commit

set -euo pipefail

# ── 定位仓库根目录 ──────────────────────────────────────────────────────────
# 使用 git rev-parse 而不是硬编码路径，保证从任意子目录调用都能定位正确。
REPO_ROOT=$(git rev-parse --show-toplevel)
HOOK_SRC="${REPO_ROOT}/scripts/pre-commit.sh"
HOOK_DST="${REPO_ROOT}/.git/hooks/pre-commit"

# ── 验证 hook 源文件存在 ────────────────────────────────────────────────────
if [ ! -f "$HOOK_SRC" ]; then
  echo "❌ 找不到 hook 源文件：${HOOK_SRC}"
  echo "   请确认你在正确的仓库根目录下运行此脚本。"
  exit 1
fi

# ── 同步给底下两个 check 脚本可执行权限 ─────────────────────────────────────
# 确保它们能被 pre-commit.sh 直接 bash 调用；幂等。
for sub in pre-commit-agents-check.sh pre-commit-swiftlint.sh; do
  chmod +x "${REPO_ROOT}/scripts/${sub}"
done

# ── 确认 .git/hooks 目录存在 ────────────────────────────────────────────────
mkdir -p "${REPO_ROOT}/.git/hooks"

# ── 复制并赋予可执行权限（幂等，覆盖旧版本）──────────────────────────────
cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"

echo "✅ pre-commit hook 已安装：${HOOK_DST}"
echo "   每次 git commit 前会依次跑："
echo "     1. AGENTS.md 文档治理检查（新增 ADR / dev-log / pitfall 必须同步索引）"
echo "     2. SwiftLint（仅检查暂存的 Swift 文件，error 阻断、warning 放行）"
echo ""
echo "   如果 swiftlint 尚未安装，第 2 步会打印提示后放行，不阻断提交。"
echo "   安装 swiftlint：brew install swiftlint"
echo ""
echo "   绕过 hook（极少情况）：git commit --no-verify"
echo "   如需卸载 hook：rm ${HOOK_DST}"
