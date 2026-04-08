#!/bin/bash

# 这个脚本用于在“无开发者会员、无正式签名”的前提下，
# 基于已经导出的 Release app 生成一个简单的手动分发 DMG。
# 它只解决“包装形态更像 macOS 安装包”的问题，不解决签名、notarization 或 Gatekeeper 信任问题。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/build/manual-release"
STAGING_DIR="$ROOT_DIR/build/dmg-staging"
APP_NAME="FeishuMeetingCountdown.app"
APP_PATH="$OUTPUT_DIR/$APP_NAME"
VERSION="$(sed -n 's/^ *MARKETING_VERSION: *//p' "$ROOT_DIR/project.yml" | head -n 1)"
BUILD_NUMBER="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *//p' "$ROOT_DIR/project.yml" | head -n 1)"
APP_BINARY_PATH="$APP_PATH/Contents/MacOS/FeishuMeetingCountdown"
ARCH_LABEL="unknown"
REUSE_EXISTING=0
VOLUME_NAME="Feishu Meeting Countdown"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"

package_suffix_for_app() {
  local app_path="$1"

  if codesign --verify --deep --strict "$app_path" >/dev/null 2>&1; then
    echo "signed"
  else
    echo "unsigned"
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

  echo "==> 使用稳定签名身份重新签名现有 app"
  codesign \
    --force \
    --deep \
    --sign "$SIGNING_IDENTITY" \
    "$app_path"

  if ! codesign --verify --deep --strict "$app_path" >/dev/null 2>&1; then
    echo "codesign 校验失败，签名后的 app 不可用于打包 DMG。" >&2
    exit 1
  fi
}

show_help() {
  cat <<'EOF'
用法:
  ./scripts/create-dmg.sh
  ./scripts/create-dmg.sh --reuse-existing
  ./scripts/create-dmg.sh --signing-identity "Your Identity"

说明:
  1. 默认会先执行 ./scripts/export-release.sh，确保手动分发 app 是最新产物
  2. 然后把 .app 和 Applications 快捷方式放进临时 staging 目录
  3. 如果传入 --signing-identity，则确保 DMG 里的 .app 带稳定代码签名
  4. 最后用 hdiutil 生成一个简单的测试版 DMG

参数:
  --reuse-existing    复用现有 build/manual-release/FeishuMeetingCountdown.app，不重新构建

注意:
  - 这是“未 notarize”的测试版 DMG
  - 如果 DMG 里仍是 unsigned app，它只能改善包装和拖拽安装体验，
    不能作为跨设备验证 Calendar / EventKit 权限的可靠安装包
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

if [[ "$REUSE_EXISTING" -eq 0 || ! -d "$APP_PATH" ]]; then
  echo "==> 先导出最新 Release app"
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    "$ROOT_DIR/scripts/export-release.sh" --signing-identity "$SIGNING_IDENTITY"
  else
    "$ROOT_DIR/scripts/export-release.sh"
  fi
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "没有找到 app: $APP_PATH" >&2
  exit 1
fi

sign_app_if_requested "$APP_PATH"

if command -v lipo >/dev/null 2>&1 && [[ -f "$APP_BINARY_PATH" ]]; then
  APP_ARCHS="$(lipo -archs "$APP_BINARY_PATH")"
  if [[ "$APP_ARCHS" == *"arm64"* && "$APP_ARCHS" == *"x86_64"* ]]; then
    ARCH_LABEL="universal"
  elif [[ -n "$APP_ARCHS" ]]; then
    ARCH_LABEL="${APP_ARCHS// /-}"
  fi
fi

PACKAGE_SUFFIX="$(package_suffix_for_app "$APP_PATH")"
DMG_NAME="FeishuMeetingCountdown-${VERSION:-0.1.0}-build${BUILD_NUMBER:-0}-${ARCH_LABEL}-${PACKAGE_SUFFIX}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

echo "==> 准备 DMG staging 目录"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> 生成 DMG"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH" >/dev/null

echo "==> 清理 staging 目录"
rm -rf "$STAGING_DIR"

echo
echo "DMG 导出完成:"
echo "  Dmg: $DMG_PATH"
echo
echo "提醒:"
if [[ "$PACKAGE_SUFFIX" == "signed" ]]; then
  echo "  当前 DMG 内的 app 已带稳定代码签名，但仍未 notarize。"
  echo "  用户首次打开时，仍可能需要在“系统设置 -> 隐私与安全性”里手动放行。"
else
  echo "  当前 DMG 内的 app 未带稳定代码签名。"
  echo "  它适合验证安装包装流程，但不适合跨设备验证 Calendar / EventKit 权限。"
fi
