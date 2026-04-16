#!/bin/bash

# 这个脚本用于在“无开发者会员、无正式签名”的前提下，
# 从当前 Xcode 工程导出可手动分发的 Release 版 app 和 zip 包。
# 默认会同时产出 Universal 与 Apple Silicon-only 两套资产，
# 方便维护者在“兼容性”和“更小包体”之间按测试对象选择。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MeetingCountdown.xcodeproj"
SCHEME_NAME="FeishuMeetingCountdown"
CONFIGURATION="Release"
DERIVED_DATA_DIR="$ROOT_DIR/build/DerivedData"
OUTPUT_DIR="$ROOT_DIR/build/manual-release"
APP_NAME="FeishuMeetingCountdown.app"
VERSION="$(sed -n 's/^ *MARKETING_VERSION: *//p' "$ROOT_DIR/project.yml" | head -n 1)"
BUILD_NUMBER="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *//p' "$ROOT_DIR/project.yml" | head -n 1)"
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

xcode_archs_for_variant() {
  local arch_variant="$1"

  case "$arch_variant" in
    universal)
      echo "arm64 x86_64"
      ;;
    arm64)
      echo "arm64"
      ;;
    *)
      echo "未知架构变体: $arch_variant" >&2
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
  # 分发包不需要保留这些本机元数据，因此签名前后统一清理，避免同一份源码在不同机器上表现不一致。
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
    echo "当前环境没有 codesign，无法使用签名身份导出分发包。" >&2
    exit 1
  fi

  echo "==> 使用稳定签名身份重新签名 app"
  clean_app_metadata "$app_path"
  codesign \
    --force \
    --deep \
    --sign "$SIGNING_IDENTITY" \
    "$app_path"

  clean_app_metadata "$app_path"

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

build_variant() {
  local arch_variant="$1"
  local xcode_archs
  local variant_derived_data_dir
  local app_source_path
  local variant_output_dir
  local copied_app_path
  local detected_arch_label
  local package_suffix
  local zip_basename
  local zip_path

  xcode_archs="$(xcode_archs_for_variant "$arch_variant")"
  variant_derived_data_dir="$DERIVED_DATA_DIR/$arch_variant"
  app_source_path="$variant_derived_data_dir/Build/Products/$CONFIGURATION/$APP_NAME"
  variant_output_dir="$OUTPUT_DIR/$arch_variant"
  copied_app_path="$variant_output_dir/$APP_NAME"

  echo "==> 开始构建 $arch_variant Release app"
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$variant_derived_data_dir" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    ONLY_ACTIVE_ARCH=NO \
    "ARCHS=$xcode_archs" \
    clean build

  if [[ ! -d "$app_source_path" ]]; then
    echo "构建完成后没有找到 app: $app_source_path" >&2
    exit 1
  fi

  echo "==> 复制 $arch_variant app 到手动分发目录"
  mkdir -p "$variant_output_dir"
  rm -rf "$copied_app_path"
  copy_app_without_local_metadata "$app_source_path" "$copied_app_path"

  echo "==> 校验 Calendar 权限说明"
  validate_calendar_usage_description "$copied_app_path"

  sign_app_if_requested "$copied_app_path"

  detected_arch_label="$(detected_arch_label_for_app "$copied_app_path")"
  if [[ "$detected_arch_label" != "$arch_variant" ]]; then
    echo "架构校验失败：期望 $arch_variant，实际 $detected_arch_label。" >&2
    exit 1
  fi

  package_suffix="$(package_suffix_for_app "$copied_app_path")"
  zip_basename="FeishuMeetingCountdown-${VERSION:-0.1.0}-build${BUILD_NUMBER:-0}-${detected_arch_label}-${package_suffix}"
  zip_path="$OUTPUT_DIR/${zip_basename}.zip"

  echo "==> 生成 $arch_variant zip 分发包"
  rm -f "$zip_path"
  ditto -c -k --norsrc --keepParent "$copied_app_path" "$zip_path"

  echo "  App: $copied_app_path"
  echo "  Zip: $zip_path"
}

show_help() {
  cat <<'EOF'
用法:
  ./scripts/export-release.sh
  ./scripts/export-release.sh --arch all
  ./scripts/export-release.sh --arch universal
  ./scripts/export-release.sh --arch arm64
  ./scripts/export-release.sh --signing-identity "Your Identity"

说明:
  1. 使用当前仓库内的 Xcode 工程执行 unsigned / ad-hoc Release build
  2. 默认同时导出 universal 和 arm64 两套 .app
  3. 把产出的 .app 分别复制到 build/manual-release/<arch>/
  4. 如果传入 --signing-identity，则在复制后的 .app 上补一个稳定代码签名
  5. 再分别生成 zip，方便手动分发或上传 GitHub Release

参数:
  --arch              选择导出架构：all、universal、arm64；默认 all
  --signing-identity  用于重新签名的稳定代码签名 identity

输出:
  - build/manual-release/universal/FeishuMeetingCountdown.app
  - build/manual-release/arm64/FeishuMeetingCountdown.app
  - build/manual-release/FeishuMeetingCountdown-<version>-build<build>-universal-<signed|unsigned>.zip
  - build/manual-release/FeishuMeetingCountdown-<version>-build<build>-arm64-<signed|unsigned>.zip

注意:
  - 这是“未 notarize”的手动分发包
  - 首次打开通常仍需要手动放行，详见 docs/manual-installation.md
  - 如果要在另一台 macOS 机器上验证 Calendar / EventKit 权限，请提供稳定签名身份；
    纯 unsigned 包只能验证 Gatekeeper 放行链路，不能可靠验证跨设备系统权限行为
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

for arch_variant in $(selected_arch_variants); do
  build_variant "$arch_variant"
done

echo
echo "Release 导出完成:"
find "$OUTPUT_DIR" -maxdepth 2 \( -name "$APP_NAME" -o -name 'FeishuMeetingCountdown-*.zip' \) -print | sed 's/^/  /'
echo
echo "提醒:"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "  当前产物已尝试使用稳定代码签名身份，但仍未 notarize。"
  echo "  测试用户首次打开时，仍可能需要在“系统设置 -> 隐私与安全性”里手动放行。"
else
  echo "  当前产物未带稳定代码签名。"
  echo "  它适合验证 Gatekeeper 放行和包装流程，但不适合跨设备验证 Calendar / EventKit 权限。"
fi
