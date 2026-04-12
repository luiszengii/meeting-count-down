#!/bin/bash

# 这个脚本用于把“构建 signed 分发产物”和“创建 GitHub Release”收口成一个本地 / CI 共用入口。
# 它的目标不是取代现有打包脚本，而是确保 tag 校验、版本校验和 gh release 上传逻辑只维护一份。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/build/manual-release"
PROJECT_VERSION="$(sed -n 's/^ *MARKETING_VERSION: *//p' "$ROOT_DIR/project.yml" | head -n 1)"
TAG_NAME=""
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
SKIP_BUILD=0

show_help() {
  cat <<'EOF'
用法:
  ./scripts/release-gh.sh --tag v1.2.3
  ./scripts/release-gh.sh --tag v1.2.3 --signing-identity "Lingjun Zeng"
  ./scripts/release-gh.sh --tag v1.2.3 --skip-build

说明:
  1. 校验 git 工作区、tag 格式和 project.yml 版本
  2. 默认调用 export-release.sh 和 create-dmg.sh 生成 Release 产物
  3. 然后使用 gh create / upload 创建或更新 GitHub Release

参数:
  --tag                目标 git tag，格式必须为 vX.Y.Z
  --signing-identity   传给分发脚本的稳定代码签名 identity
  --skip-build         复用现有 build/manual-release/ 产物，不重新构建

注意:
  - 本脚本默认要求当前工作区干净，避免把“源码和 release 资产来自不同状态”的情况发出去
  - Release notes 使用 gh 的 --generate-notes
  - 已存在的同名 Release 会执行 upload --clobber 覆盖资产
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      if [[ $# -lt 2 ]]; then
        echo "--tag 需要跟一个 vX.Y.Z 版本号。" >&2
        exit 1
      fi

      TAG_NAME="$2"
      shift 2
      ;;
    --signing-identity)
      if [[ $# -lt 2 ]]; then
        echo "--signing-identity 需要跟一个签名身份名称。" >&2
        exit 1
      fi

      SIGNING_IDENTITY="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      show_help >&2
      exit 1
      ;;
  esac
done

if [[ -z "$TAG_NAME" ]]; then
  echo "必须通过 --tag 指定目标版本。" >&2
  exit 1
fi

if [[ ! "$TAG_NAME" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "tag 格式不合法: $TAG_NAME。期望格式为 vX.Y.Z。" >&2
  exit 1
fi

if [[ ! -d "$ROOT_DIR/.git" ]]; then
  echo "当前目录不是一个 git 仓库根目录: $ROOT_DIR" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "当前环境没有 gh，无法创建 GitHub Release。" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "当前环境没有 git，无法校验发布状态。" >&2
  exit 1
fi

if ! git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
  echo "当前仓库中不存在 tag: $TAG_NAME" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "当前 git 工作区不干净，请先提交或清理改动后再发布。" >&2
  exit 1
fi

TAG_VERSION="${TAG_NAME#v}"
if [[ "$PROJECT_VERSION" != "$TAG_VERSION" ]]; then
  echo "project.yml 中的 MARKETING_VERSION ($PROJECT_VERSION) 与 tag ($TAG_VERSION) 不一致。" >&2
  exit 1
fi

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    "$ROOT_DIR/scripts/export-release.sh" --signing-identity "$SIGNING_IDENTITY"
    "$ROOT_DIR/scripts/create-dmg.sh" --reuse-existing --signing-identity "$SIGNING_IDENTITY"
  else
    "$ROOT_DIR/scripts/export-release.sh"
    "$ROOT_DIR/scripts/create-dmg.sh" --reuse-existing
  fi
fi

shopt -s nullglob
release_assets=(
  "$OUTPUT_DIR"/FeishuMeetingCountdown-"$TAG_VERSION"-build*.zip
  "$OUTPUT_DIR"/FeishuMeetingCountdown-"$TAG_VERSION"-build*.dmg
)
shopt -u nullglob

if [[ "${#release_assets[@]}" -eq 0 ]]; then
  echo "没有在 $OUTPUT_DIR 中找到可上传的 release 产物。" >&2
  exit 1
fi

if gh release view "$TAG_NAME" >/dev/null 2>&1; then
  echo "==> 更新现有 GitHub Release: $TAG_NAME"
  gh release upload "$TAG_NAME" "${release_assets[@]}" --clobber
else
  echo "==> 创建新的 GitHub Release: $TAG_NAME"
  gh release create "$TAG_NAME" "${release_assets[@]}" --generate-notes
fi
