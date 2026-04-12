#!/bin/bash

# 这个脚本用于在“无开发者会员、无正式签名”的前提下，
# 从当前 Xcode 工程导出一个可手动分发的 Release 版 app 和 zip 包。
# 它的目标不是替代正式发布流程，而是稳定产出给小范围测试用户使用的安装包。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MeetingCountdown.xcodeproj"
SCHEME_NAME="FeishuMeetingCountdown"
CONFIGURATION="Release"
DERIVED_DATA_DIR="$ROOT_DIR/build/DerivedData"
OUTPUT_DIR="$ROOT_DIR/build/manual-release"
APP_NAME="FeishuMeetingCountdown.app"
APP_SOURCE_PATH="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME"
VERSION="$(sed -n 's/^ *MARKETING_VERSION: *//p' "$ROOT_DIR/project.yml" | head -n 1)"
BUILD_NUMBER="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *//p' "$ROOT_DIR/project.yml" | head -n 1)"
COPIED_APP_PATH="$OUTPUT_DIR/$APP_NAME"
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
    echo "当前环境没有 codesign，无法使用签名身份导出分发包。" >&2
    exit 1
  fi

  echo "==> 使用稳定签名身份重新签名 app"
  codesign \
    --force \
    --deep \
    --sign "$SIGNING_IDENTITY" \
    "$app_path"

  if ! codesign --verify --deep --strict "$app_path" >/dev/null 2>&1; then
    echo "codesign 校验失败，签名后的 app 不可用于分发。" >&2
    exit 1
  fi
}

validate_calendar_usage_description() {
  local app_path="$1"
  local info_plist="$app_path/Contents/Info.plist"
  local usage_description=""

  if [[ ! -f "$info_plist" ]]; then
    echo "没有找到 Info.plist: $info_plist" >&2
    exit 1
  fi

  usage_description="$(/usr/libexec/PlistBuddy -c 'Print :NSCalendarsFullAccessUsageDescription' "$info_plist" 2>/dev/null || true)"

  if [[ -z "$usage_description" ]]; then
    echo "导出的 app 缺少 NSCalendarsFullAccessUsageDescription，当前产物不能正常申请 Calendar 权限。" >&2
    exit 1
  fi
}

show_help() {
  cat <<'EOF'
用法:
  ./scripts/export-release.sh
  ./scripts/export-release.sh --signing-identity "Your Identity"

说明:
  1. 使用当前仓库内的 Xcode 工程执行一次 unsigned / ad-hoc Release build
  2. 把产出的 .app 复制到 build/manual-release/
  3. 如果传入 --signing-identity，则在复制后的 .app 上补一个稳定代码签名
  4. 再额外打一个 zip，方便手动分发

输出:
  - build/manual-release/FeishuMeetingCountdown.app
  - build/manual-release/FeishuMeetingCountdown-<version>-build<build>-<arch>-<signed|unsigned>.zip

注意:
  - 这是“未 notarize”的手动分发包
  - 首次打开通常仍需要手动放行，详见 docs/manual-installation.md
  - 如果要在另一台 macOS 机器上验证 Calendar / EventKit 权限，请提供稳定签名身份；
    纯 unsigned 包只能验证 Gatekeeper 放行链路，不能可靠验证跨设备系统权限行为
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "未找到工程目录: $PROJECT_PATH" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "当前环境没有 xcodebuild，无法导出 Release 安装包。" >&2
  exit 1
fi

echo "==> 清理旧的手动分发产物"
rm -rf "$DERIVED_DATA_DIR" "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "==> 开始构建 unsigned Release app"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  clean build

if [[ ! -d "$APP_SOURCE_PATH" ]]; then
  echo "构建完成后没有找到 app: $APP_SOURCE_PATH" >&2
  exit 1
fi

echo "==> 复制 app 到手动分发目录"
cp -R "$APP_SOURCE_PATH" "$COPIED_APP_PATH"

echo "==> 校验 Calendar 权限说明"
validate_calendar_usage_description "$COPIED_APP_PATH"

sign_app_if_requested "$COPIED_APP_PATH"

APP_BINARY_PATH="$COPIED_APP_PATH/Contents/MacOS/FeishuMeetingCountdown"
ARCH_LABEL="unknown"
PACKAGE_SUFFIX="$(package_suffix_for_app "$COPIED_APP_PATH")"

if command -v lipo >/dev/null 2>&1 && [[ -f "$APP_BINARY_PATH" ]]; then
  APP_ARCHS="$(lipo -archs "$APP_BINARY_PATH")"
  if [[ "$APP_ARCHS" == *"arm64"* && "$APP_ARCHS" == *"x86_64"* ]]; then
    ARCH_LABEL="universal"
  elif [[ -n "$APP_ARCHS" ]]; then
    ARCH_LABEL="${APP_ARCHS// /-}"
  fi
fi

ZIP_BASENAME="FeishuMeetingCountdown-${VERSION:-0.1.0}-build${BUILD_NUMBER:-0}-${ARCH_LABEL}-${PACKAGE_SUFFIX}"
ZIP_PATH="$OUTPUT_DIR/${ZIP_BASENAME}.zip"

echo "==> 生成 zip 分发包"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$COPIED_APP_PATH" "$ZIP_PATH"

echo
echo "Release 导出完成:"
echo "  App: $COPIED_APP_PATH"
echo "  Zip: $ZIP_PATH"
echo
echo "提醒:"
if [[ "$PACKAGE_SUFFIX" == "signed" ]]; then
  echo "  当前产物已带稳定代码签名，但仍未 notarize。"
  echo "  测试用户首次打开时，仍可能需要在“系统设置 -> 隐私与安全性”里手动放行。"
else
  echo "  当前产物未带稳定代码签名。"
  echo "  它适合验证 Gatekeeper 放行和包装流程，但不适合跨设备验证 Calendar / EventKit 权限。"
fi
