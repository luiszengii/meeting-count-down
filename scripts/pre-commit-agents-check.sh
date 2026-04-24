#!/usr/bin/env bash
# scripts/pre-commit-agents-check.sh
#
# 目的：作为 Git pre-commit hook 的一部分，机械检查本次 commit 是否违反
#       AGENTS.md 里能机械化校验的几条文档治理规则。
#
# 当前覆盖的规则（来自根 AGENTS.md 与 docs/index.md 的"文档治理"段落）：
#
#   规则 #1：新增 docs/adrs/YYYY-MM-DD-*.md 必须同时更新
#            docs/adrs/README.md 与 docs/index.md。
#
#   规则 #2：新增 docs/dev-logs/YYYY-MM-DD.md 必须同时更新
#            docs/dev-logs/README.md 与 docs/index.md。
#
#   规则 #3：新增 docs/pitfalls/*.md（README.md 除外）必须同时更新
#            docs/pitfalls/README.md 与 docs/index.md。
#
#   规则 #4：上述三个 README/index 的更新必须真的提到了新文件名，
#            而不仅仅是 touch 了文件。
#
# 行为：
#   - 任何规则违反 → 打印明确的修复指引，exit 1 阻断提交。
#   - 全部通过或没有相关 staged 变更 → exit 0 放行。
#
# 安装方式：通过 scripts/install-pre-commit-hook.sh 一次性挂上去。
# 这个脚本本身可以独立运行做 dry-check：
#   bash scripts/pre-commit-agents-check.sh

set -euo pipefail

# ── 收集本次 commit 中"新增"的文件 ──────────────────────────────────────────
# --diff-filter=A：只看 Added (新增) 的文件。修改/重命名/删除暂不在 v1 范围。
ADDED_FILES=$(git diff --cached --name-only --diff-filter=A 2>/dev/null || true)

if [ -z "$ADDED_FILES" ]; then
  exit 0
fi

# ── 收集本次 commit 中所有变更（用于判断 README/index 是否被同步更新）─────
# --diff-filter=ACMR：新增 + 复制 + 修改 + 重命名都算"被 touch"。
TOUCHED_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)

# ── 工具函数：检查某文件是否在 staged 变更里被 touch ──────────────────────
file_touched() {
  echo "$TOUCHED_FILES" | grep -qFx "$1"
}

# ── 工具函数：检查 staged 版本的 README/index 文件内容里有没有提到某个文件名 ─
# 用 git show :path 拿暂存区版本，避免依赖 working tree。
staged_content_mentions() {
  local file="$1"
  local needle="$2"
  git show ":${file}" 2>/dev/null | grep -qF "$needle"
}

VIOLATIONS=()

# ── 规则 #1：ADR ────────────────────────────────────────────────────────────
NEW_ADRS=$(echo "$ADDED_FILES" | grep -E '^docs/adrs/[0-9]{4}-[0-9]{2}-[0-9]{2}-.+\.md$' || true)
for adr in $NEW_ADRS; do
  basename=$(basename "$adr")

  if ! file_touched "docs/adrs/README.md"; then
    VIOLATIONS+=("[ADR] 新增 ${adr} 但 docs/adrs/README.md 未被同步更新。")
  elif ! staged_content_mentions "docs/adrs/README.md" "$basename"; then
    VIOLATIONS+=("[ADR] 新增 ${adr}，docs/adrs/README.md 被 touch 了但不包含新文件名 ${basename}。")
  fi

  if ! file_touched "docs/index.md"; then
    VIOLATIONS+=("[ADR] 新增 ${adr} 但 docs/index.md 未被同步更新（违反根 AGENTS.md 文档治理）。")
  elif ! staged_content_mentions "docs/index.md" "$basename"; then
    VIOLATIONS+=("[ADR] 新增 ${adr}，docs/index.md 被 touch 了但不包含新文件名 ${basename}。")
  fi
done

# ── 规则 #2：Dev log ───────────────────────────────────────────────────────
NEW_LOGS=$(echo "$ADDED_FILES" | grep -E '^docs/dev-logs/[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$' || true)
for log in $NEW_LOGS; do
  basename=$(basename "$log")

  if ! file_touched "docs/dev-logs/README.md"; then
    VIOLATIONS+=("[Dev Log] 新增 ${log} 但 docs/dev-logs/README.md 未被同步更新。")
  elif ! staged_content_mentions "docs/dev-logs/README.md" "$basename"; then
    VIOLATIONS+=("[Dev Log] 新增 ${log}，docs/dev-logs/README.md 被 touch 了但不包含新文件名 ${basename}。")
  fi

  if ! file_touched "docs/index.md"; then
    VIOLATIONS+=("[Dev Log] 新增 ${log} 但 docs/index.md 未被同步更新。")
  elif ! staged_content_mentions "docs/index.md" "$basename"; then
    VIOLATIONS+=("[Dev Log] 新增 ${log}，docs/index.md 被 touch 了但不包含新文件名 ${basename}。")
  fi
done

# ── 规则 #3：Pitfall ───────────────────────────────────────────────────────
# README.md 除外（README.md 是索引本身，不是 pitfall）。
NEW_PITFALLS=$(echo "$ADDED_FILES" | grep -E '^docs/pitfalls/.+\.md$' | grep -v '/README\.md$' || true)
for pitfall in $NEW_PITFALLS; do
  basename=$(basename "$pitfall")

  if ! file_touched "docs/pitfalls/README.md"; then
    VIOLATIONS+=("[Pitfall] 新增 ${pitfall} 但 docs/pitfalls/README.md 未被同步更新。")
  elif ! staged_content_mentions "docs/pitfalls/README.md" "$basename"; then
    VIOLATIONS+=("[Pitfall] 新增 ${pitfall}，docs/pitfalls/README.md 被 touch 了但不包含新文件名 ${basename}。")
  fi

  if ! file_touched "docs/index.md"; then
    VIOLATIONS+=("[Pitfall] 新增 ${pitfall} 但 docs/index.md 未被同步更新。")
  elif ! staged_content_mentions "docs/index.md" "$basename"; then
    VIOLATIONS+=("[Pitfall] 新增 ${pitfall}，docs/index.md 被 touch 了但不包含新文件名 ${basename}。")
  fi
done

# ── 输出结果 ───────────────────────────────────────────────────────────────
if [ ${#VIOLATIONS[@]} -eq 0 ]; then
  # 有相关 staged 变更但全部检查通过；保持安静以免噪音。
  exit 0
fi

echo ""
echo "❌ AGENTS.md 文档治理规则检查未通过，提交已阻断。"
echo ""
echo "   根 AGENTS.md 与 docs/index.md 都明确要求："
echo "   新增正式文档（ADR / dev-log / pitfall）时必须同步更新对应 README 和全局 index。"
echo ""
echo "   违规列表："
echo ""
for v in "${VIOLATIONS[@]}"; do
  echo "   • $v"
done
echo ""
echo "   修复方式："
echo "   1. 在 docs/adrs/README.md / docs/dev-logs/README.md / docs/pitfalls/README.md 里"
echo "      加入新文件的相对链接条目。"
echo "   2. 在 docs/index.md 对应表格里加入条目（ADR / 开发日志 / Pitfalls 段落）。"
echo "   3. git add 修改后的 README 和 index，重新 commit。"
echo ""
echo "   如果你确定要绕过此检查（极少情况，例如批量历史回填），可以："
echo "      git commit --no-verify"
echo "   但这条命令会同时跳过 SwiftLint 检查，请确保你清楚后果。"
echo ""

exit 1
