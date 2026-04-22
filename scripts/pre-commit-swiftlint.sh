#!/usr/bin/env bash
# scripts/pre-commit-swiftlint.sh
#
# 目的：作为 Git pre-commit hook 的主体，在提交前对本次暂存的 Swift 文件
#       执行 SwiftLint 检查。只检查 staged 文件，不扫描全仓库，保证速度。
#
# 行为：
#   1. 如果 swiftlint 未安装 → 打印提示后放行（exit 0），不阻断提交。
#   2. 如果没有暂存的 .swift 文件 → 直接放行（exit 0）。
#   3. 如果 swiftlint 发现错误 → 打印结果并 exit 1，阻断提交。
#   4. 只有 warning 时不阻断（--strict 仅在 CI 中使用，本地 hook 不传此标志）。
#
# 安装方式：运行 scripts/install-pre-commit-hook.sh 一次即可。
# 手动卸载：删除 .git/hooks/pre-commit 文件。

set -euo pipefail

# ── 1. 检测 swiftlint 是否可用 ─────────────────────────────────────────────
if ! command -v swiftlint >/dev/null 2>&1; then
  echo "⚠️  swiftlint 未安装，跳过 lint 检查。如需启用，请运行：brew install swiftlint"
  exit 0
fi

# ── 2. 收集本次 commit 中暂存的 Swift 文件 ────────────────────────────────
# --diff-filter=ACM：只看新增(A)、复制(C)、修改(M)的文件，跳过已删除文件。
STAGED_SWIFT_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$' || true)

if [ -z "$STAGED_SWIFT_FILES" ]; then
  # 没有暂存的 Swift 文件，无需 lint
  exit 0
fi

echo "🔍 SwiftLint：检查 $(echo "$STAGED_SWIFT_FILES" | wc -l | tr -d ' ') 个暂存 Swift 文件…"

# ── 3. 把文件列表通过环境变量传给 swiftlint ───────────────────────────────
# SCRIPT_INPUT_FILE_COUNT + SCRIPT_INPUT_FILE_n 是 swiftlint 支持的协议，
# 可以精确告诉它只 lint 哪些文件，而不是扫整个 included 目录。
FILE_COUNT=0
while IFS= read -r FILE; do
  export "SCRIPT_INPUT_FILE_${FILE_COUNT}=${FILE}"
  FILE_COUNT=$((FILE_COUNT + 1))
done <<< "$STAGED_SWIFT_FILES"
export SCRIPT_INPUT_FILE_COUNT=$FILE_COUNT

# --quiet：只输出 warning/error，不打印 "Linting X files" 等噪音。
# --use-script-input-files：读取上面设置的环境变量而不是扫目录。
# 注意：本地 hook 不传 --strict，warning 不阻断提交；error 才阻断。
LINT_OUTPUT=$(swiftlint lint --quiet --use-script-input-files 2>&1 || true)

# ── 4. 判断是否有 error 级别的问题 ────────────────────────────────────────
# swiftlint 输出格式：path:line:col: error: message (RuleName)
if echo "$LINT_OUTPUT" | grep -q ': error:'; then
  echo ""
  echo "❌ SwiftLint 发现 error，提交已阻断。请修复以下问题后重新提交："
  echo ""
  echo "$LINT_OUTPUT"
  echo ""
  exit 1
fi

# 有 warning 时打印但不阻断
if [ -n "$LINT_OUTPUT" ]; then
  echo "⚠️  SwiftLint warning（不阻断提交）："
  echo "$LINT_OUTPUT"
fi

echo "✅ SwiftLint 检查通过"
exit 0
