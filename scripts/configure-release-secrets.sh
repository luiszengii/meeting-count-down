#!/bin/bash

# 这个脚本用于把本机已有的代码签名 identity 导出为临时 .p12，
# 然后写入 GitHub Release workflow 需要的四个 repo secrets。
# 如果钥匙串对私钥导出有访问控制，脚本运行时可能会弹出系统授权框，维护者需要在本机确认一次。

set -euo pipefail

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
KEYCHAIN_PATH="${KEYCHAIN_PATH:-}"

resolve_keychain_path() {
  local requested_path="$1"
  local -a candidates=()
  local default_keychain=""
  local login_keychain=""
  local candidate=""

  if [[ -n "$requested_path" ]]; then
    candidates+=("$requested_path")
  fi

  default_keychain="$(security default-keychain -d user 2>/dev/null | tr -d '"' | xargs || true)"
  if [[ -n "$default_keychain" ]]; then
    candidates+=("$default_keychain")
  fi

  login_keychain="$(security login-keychain 2>/dev/null | tr -d '"' | xargs || true)"
  if [[ -n "$login_keychain" ]]; then
    candidates+=("$login_keychain")
  fi

  if [[ -d "$HOME/Library/Keychains" ]]; then
    while IFS= read -r candidate; do
      candidates+=("$candidate")
    done < <(find "$HOME/Library/Keychains" -maxdepth 1 -type f \( -name '*.keychain-db' -o -name '*.keychain' \) | sort)
  fi

  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]] && security find-identity -v -p codesigning "$candidate" | rg -F "\"$SIGNING_IDENTITY\"" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

show_help() {
  cat <<'EOF'
用法:
  ./scripts/configure-release-secrets.sh --signing-identity "Lingjun Zeng"

说明:
  1. 从指定 keychain 导出现有代码签名 identity 的 .p12
  2. 自动生成 .p12 密码和临时 keychain 密码
  3. 使用 gh secret set 写入当前仓库需要的 4 个 GitHub secrets

参数:
  --signing-identity   要导出的代码签名 identity 名称
  --keychain-path      要读取的 keychain 路径，默认是 login.keychain-db

注意:
  - 运行过程中如果 macOS 弹出“允许导出私钥”的钥匙串授权框，需要在本机确认
  - 脚本不会把生成的密码写回仓库，也不会把 .p12 留在磁盘上
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
    --keychain-path)
      if [[ $# -lt 2 ]]; then
        echo "--keychain-path 需要跟一个 keychain 路径。" >&2
        exit 1
      fi

      KEYCHAIN_PATH="$2"
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

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "必须通过 --signing-identity 指定要导出的 identity。" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "当前环境没有 gh，无法写入 GitHub secrets。" >&2
  exit 1
fi

if ! command -v security >/dev/null 2>&1; then
  echo "当前环境没有 security，无法导出代码签名 identity。" >&2
  exit 1
fi

RESOLVED_KEYCHAIN_PATH="$(resolve_keychain_path "$KEYCHAIN_PATH" || true)"
if [[ -z "$RESOLVED_KEYCHAIN_PATH" ]]; then
  echo "没有找到包含代码签名 identity \"$SIGNING_IDENTITY\" 的可用 keychain。" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "当前 gh 认证不可用，无法写入 GitHub secrets；请先执行 gh auth login -h github.com。" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

P12_PATH="$TMP_DIR/release-signing-identity.p12"
P12_PASSWORD="$(openssl rand -base64 24 | tr -d '\n')"
KEYCHAIN_PASSWORD="$(openssl rand -base64 24 | tr -d '\n')"

echo "==> 从本机 keychain 导出 identity"
echo "使用的 keychain: $RESOLVED_KEYCHAIN_PATH"
echo "如果系统弹出钥匙串授权框，请允许当前终端导出私钥。"
security export \
  -k "$RESOLVED_KEYCHAIN_PATH" \
  -t identities \
  -f pkcs12 \
  -P "$P12_PASSWORD" \
  -o "$P12_PATH" >/dev/null

if [[ ! -s "$P12_PATH" ]]; then
  echo "导出的 .p12 文件为空，无法继续配置 GitHub secrets。" >&2
  exit 1
fi

echo "==> 写入 GitHub repo secrets"
gh secret set MACOS_SIGNING_IDENTITY --body "$SIGNING_IDENTITY" >/dev/null
gh secret set MACOS_CERTIFICATE_PASSWORD --body "$P12_PASSWORD" >/dev/null
gh secret set MACOS_KEYCHAIN_PASSWORD --body "$KEYCHAIN_PASSWORD" >/dev/null
base64 -i "$P12_PATH" | tr -d '\n' | gh secret set MACOS_CERTIFICATE_P12_BASE64 >/dev/null

echo "已写入以下 GitHub secrets:"
gh secret list | rg '^MACOS_'
