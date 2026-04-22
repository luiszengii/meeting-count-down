#!/usr/bin/env bash
# scripts/install-pre-commit-hook.sh
#
# 目的：把 scripts/pre-commit-swiftlint.sh 复制到 .git/hooks/pre-commit，
#       使其在每次 git commit 前自动运行 SwiftLint。
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
HOOK_SRC="${REPO_ROOT}/scripts/pre-commit-swiftlint.sh"
HOOK_DST="${REPO_ROOT}/.git/hooks/pre-commit"

# ── 验证 hook 源文件存在 ────────────────────────────────────────────────────
if [ ! -f "$HOOK_SRC" ]; then
  echo "❌ 找不到 hook 源文件：${HOOK_SRC}"
  echo "   请确认你在正确的仓库根目录下运行此脚本。"
  exit 1
fi

# ── 确认 .git/hooks 目录存在 ────────────────────────────────────────────────
mkdir -p "${REPO_ROOT}/.git/hooks"

# ── 复制并赋予可执行权限（幂等，覆盖旧版本）──────────────────────────────
cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"

echo "✅ pre-commit hook 已安装：${HOOK_DST}"
echo "   每次 git commit 前会自动对暂存的 Swift 文件运行 SwiftLint。"
echo ""
echo "   如果 swiftlint 尚未安装，hook 会打印提示后放行，不阻断提交。"
echo "   安装 swiftlint：brew install swiftlint"
echo ""
echo "   如需卸载 hook：rm ${HOOK_DST}"
