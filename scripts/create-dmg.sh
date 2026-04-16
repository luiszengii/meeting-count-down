#!/bin/bash

# 这个脚本用于在“无开发者会员、无正式签名”的前提下，
# 基于已经导出的 Release app 生成简单的手动分发 DMG。
# 默认会为 universal 和 arm64 两套 app 各生成一个 DMG，
# 让 GitHub Release 同时提供兼容包和更小的 Apple Silicon-only 包。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/build/manual-release"
STAGING_ROOT="$ROOT_DIR/build/dmg-staging"
APP_NAME="FeishuMeetingCountdown.app"
VERSION="$(sed -n 's/^ *MARKETING_VERSION: *//p' "$ROOT_DIR/project.yml" | head -n 1)"
BUILD_NUMBER="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *//p' "$ROOT_DIR/project.yml" | head -n 1)"
REUSE_EXISTING=0
VOLUME_NAME="Feishu Meeting Countdown"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
ARCH_SELECTOR="all"

selected_arch_variants() {
  case "$ARCH_SELECTOR" in
    all)
      echo "universal arm64"
      ;;
    universal|arm64)
      echo "$ARCH_SELECTOR"
      ;;
    *)
      echo "未知架构选择: $ARCH_SELECTOR" >&2
      exit 1
      ;;
  esac
}

package_suffix_for_app() {
  local app_path="$1"

  # 这里判断的是“是否存在稳定代码签名身份”，而不是“当前文件系统状态下是否通过 strict 校验”。
  # FinderInfo 之类的本机元数据可能让 strict verify 暂时失败，但不等于产物已经退回 unsigned。
  if codesign -dv "$app_path" >/dev/null 2>&1; then
    echo "signed"
  else
    echo "unsigned"
  fi
}

clean_app_metadata() {
  local app_path="$1"

  if ! command -v xattr >/dev/null 2>&1; then
    return 0
  fi

  # FinderInfo、resource fork 和 provenance 这类扩展属性会让 codesign 拒绝签名。
  # DMG 只需要 app 的实际 bundle 内容，不应把维护机上的本地元数据带进签名步骤。
  xattr -cr "$app_path"
}

copy_app_without_local_metadata() {
  local source_path="$1"
  local destination_path="$2"

  if command -v ditto >/dev/null 2>&1; then
    ditto --norsrc "$source_path" "$destination_path"
  else
    cp -R "$source_path" "$destination_path"
    clean_app_metadata "$destination_path"
  fi
}

sign_app_if_requested() {
  local app_path="$1"

  if [[ -z "$SIGNING_IDENTITY" ]]; then
    return 0
  fi

  if ! command -v codesign >/dev/null 2>&1; then
    echo "当前环境没有 codesign，无法使用签名身份导出 DMG。" >&2
    exit 1
  fi

  echo "==> 使用稳定签名身份重新签名 $app_path"
  clean_app_metadata "$app_path"
  codesign \
    --force \
    --deep \
    --sign "$SIGNING_IDENTITY" \
    "$app_path"

  clean_app_metadata "$app_path"

  if ! codesign --verify --deep --strict "$app_path" >/dev/null 2>&1; then
    echo "codesign 校验失败，签名后的 app 不可用于打包 DMG。" >&2
    exit 1
  fi
}

detected_arch_label_for_app() {
  local app_path="$1"
  local binary_path="$app_path/Contents/MacOS/FeishuMeetingCountdown"
  local app_archs=""

  if command -v lipo >/dev/null 2>&1 && [[ -f "$binary_path" ]]; then
    app_archs="$(lipo -archs "$binary_path")"
    if [[ "$app_archs" == *"arm64"* && "$app_archs" == *"x86_64"* ]]; then
      echo "universal"
      return 0
    elif [[ -n "$app_archs" ]]; then
      echo "${app_archs// /-}"
      return 0
    fi
  fi

  echo "unknown"
}

has_all_selected_apps() {
  local arch_variant

  for arch_variant in $(selected_arch_variants); do
    if [[ ! -d "$OUTPUT_DIR/$arch_variant/$APP_NAME" ]]; then
      return 1
    fi
  done

  return 0
}

build_dmg_for_variant() {
  local arch_variant="$1"
  local app_path="$OUTPUT_DIR/$arch_variant/$APP_NAME"
  local detected_arch_label
  local package_suffix
  local dmg_name
  local dmg_path
  local staging_dir="$STAGING_ROOT/$arch_variant"

  if [[ ! -d "$app_path" ]]; then
    echo "没有找到 $arch_variant app: $app_path" >&2
    exit 1
  fi

  if [[ "$REUSE_EXISTING" -eq 1 && -n "$SIGNING_IDENTITY" ]]; then
    sign_app_if_requested "$app_path"
  fi

  detected_arch_label="$(detected_arch_label_for_app "$app_path")"
  if [[ "$detected_arch_label" != "$arch_variant" ]]; then
    echo "架构校验失败：期望 $arch_variant，实际 $detected_arch_label。" >&2
    exit 1
  fi

  package_suffix="$(package_suffix_for_app "$app_path")"
  dmg_name="FeishuMeetingCountdown-${VERSION:-0.1.0}-build${BUILD_NUMBER:-0}-${detected_arch_label}-${package_suffix}.dmg"
  dmg_path="$OUTPUT_DIR/$dmg_name"

  echo "==> 准备 $arch_variant DMG staging 目录"
  rm -rf "$staging_dir"
  mkdir -p "$staging_dir"
  copy_app_without_local_metadata "$app_path" "$staging_dir/$APP_NAME"
  ln -s /Applications "$staging_dir/Applications"

  echo "==> 生成 $arch_variant DMG"
  rm -f "$dmg_path"
  hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -ov \
    "$dmg_path" >/dev/null

  echo "  Dmg: $dmg_path"
}

show_help() {
  cat <<'EOF'
用法:
  ./scripts/create-dmg.sh
  ./scripts/create-dmg.sh --arch all
  ./scripts/create-dmg.sh --arch universal
  ./scripts/create-dmg.sh --arch arm64
  ./scripts/create-dmg.sh --reuse-existing
  ./scripts/create-dmg.sh --signing-identity "Your Identity"

说明:
  1. 默认会先执行 ./scripts/export-release.sh --arch all，确保手动分发 app 是最新产物
  2. 然后为每套 .app 各自生成 DMG
  3. 如果传入 --signing-identity，则确保 DMG 里的 .app 带稳定代码签名
  4. 最后用 hdiutil 生成简单的测试版 DMG

参数:
  --arch              选择导出架构：all、universal、arm64；默认 all
  --reuse-existing    复用现有 build/manual-release/<arch>/FeishuMeetingCountdown.app，不重新构建

注意:
  - 这是“未 notarize”的测试版 DMG
  - 如果 DMG 里仍是 unsigned app，它只能改善包装和拖拽安装体验，
    不能作为跨设备验证 Calendar / EventKit 权限的可靠安装包
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      if [[ $# -lt 2 ]]; then
        echo "--arch 需要跟 all、universal 或 arm64。" >&2
        exit 1
      fi

      ARCH_SELECTOR="$2"
      shift 2
      ;;
    --reuse-existing)
      REUSE_EXISTING=1
      shift
      ;;
    --signing-identity)
      if [[ $# -lt 2 ]]; then
        echo "--signing-identity 需要跟一个签名身份名称。" >&2
        exit 1
      fi

      SIGNING_IDENTITY="$2"
      shift 2
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

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "当前环境没有 hdiutil，无法生成 DMG。" >&2
  exit 1
fi

if [[ "$REUSE_EXISTING" -eq 0 ]] || ! has_all_selected_apps; then
  echo "==> 先导出最新 Release app"
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    "$ROOT_DIR/scripts/export-release.sh" --arch "$ARCH_SELECTOR" --signing-identity "$SIGNING_IDENTITY"
  else
    "$ROOT_DIR/scripts/export-release.sh" --arch "$ARCH_SELECTOR"
  fi
fi

rm -rf "$STAGING_ROOT"
mkdir -p "$STAGING_ROOT"

for arch_variant in $(selected_arch_variants); do
  build_dmg_for_variant "$arch_variant"
done

echo "==> 清理 staging 目录"
rm -rf "$STAGING_ROOT"

echo
echo "DMG 导出完成:"
find "$OUTPUT_DIR" -maxdepth 1 -name 'FeishuMeetingCountdown-*.dmg' -print | sed 's/^/  /'
echo
echo "提醒:"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "  当前 DMG 内的 app 已尝试使用稳定代码签名身份，但仍未 notarize。"
  echo "  用户首次打开时，仍可能需要在“系统设置 -> 隐私与安全性”里手动放行。"
else
  echo "  当前 DMG 内的 app 未带稳定代码签名。"
  echo "  它适合验证安装包装流程，但不适合跨设备验证 Calendar / EventKit 权限。"
fi
