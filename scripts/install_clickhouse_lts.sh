#!/usr/bin/env bash
# Installs the ClickHouse LTS binary into a user-defined bin directory.
set -euo pipefail

VERSION="v25.3.7.194-lts"
ASSET_NAME="${ASSET_NAME:-}"
ASSET_TYPE="${ASSET_TYPE:-}"
RELEASE_URL_BASE="https://github.com/ClickHouse/ClickHouse/releases/download"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
BINARY_NAME="${BINARY_NAME:-clickhouse}"
FORCE="false"

usage() {
  cat <<'USAGE'
Usage: install_clickhouse_lts.sh [options]

Options:
  --install-dir <path>   Target directory for the ClickHouse binary (default: $HOME/.local/bin)
  --binary-name <name>   Name for the installed binary (default: clickhouse)
  --version <tag>        Release tag to install (default: v25.3.7.194-lts)
  --asset-name <name>    Release asset to download (auto-detected when possible)
  --asset-type <type>    Asset type: binary or tar (auto-detected when possible)
  --force                Overwrite any existing binary in the target location
  -h, --help             Show this help message

Environment overrides:
  INSTALL_DIR, BINARY_NAME, VERSION, ASSET_NAME, ASSET_TYPE

The script refuses to install into /opt/homebrew/bin to avoid overwriting Homebrew-managed files.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir)
      [[ $# -lt 2 ]] && { echo "Missing value for --install-dir" >&2; exit 1; }
      INSTALL_DIR="$2"
      shift 2
      ;;
    --binary-name)
      [[ $# -lt 2 ]] && { echo "Missing value for --binary-name" >&2; exit 1; }
      BINARY_NAME="$2"
      shift 2
      ;;
    --version)
      [[ $# -lt 2 ]] && { echo "Missing value for --version" >&2; exit 1; }
      VERSION="$2"
      shift 2
      ;;
    --force)
      FORCE="true"
      shift
      ;;
    --asset-name)
      [[ $# -lt 2 ]] && { echo "Missing value for --asset-name" >&2; exit 1; }
      ASSET_NAME="$2"
      shift 2
      ;;
    --asset-type)
      [[ $# -lt 2 ]] && { echo "Missing value for --asset-type" >&2; exit 1; }
      ASSET_TYPE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$INSTALL_DIR" == "/opt/homebrew/bin" ]]; then
  echo "Refusing to install into /opt/homebrew/bin. Choose another --install-dir." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required but not found in PATH." >&2
  exit 1
fi

detect_default_asset() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "${os}:${arch}" in
    Darwin:arm64)
      echo "clickhouse-macos-aarch64:binary"
      ;;
    Darwin:x86_64)
      echo "clickhouse-macos-x86_64:binary"
      ;;
    Linux:x86_64)
      echo "clickhouse-common-static:tar"
      ;;
    Linux:arm64|Linux:aarch64)
      echo "clickhouse-common-static-aarch64:tar"
      ;;
    *)
      return 1
      ;;
  esac
}

if [[ -z "$ASSET_NAME" || -z "$ASSET_TYPE" ]]; then
  if defaults=$(detect_default_asset); then
    ASSET_NAME="${ASSET_NAME:-${defaults%%:*}}"
    ASSET_TYPE="${ASSET_TYPE:-${defaults##*:}}"
  else
    echo "Unable to detect a default asset for this platform. Specify --asset-name and --asset-type." >&2
    exit 1
  fi
fi

case "$ASSET_TYPE" in
  binary|tar)
    ;;
  *)
    echo "Unsupported asset type: $ASSET_TYPE (expected 'binary' or 'tar')." >&2
    exit 1
    ;;
esac

DOWNLOAD_URL="$RELEASE_URL_BASE/$VERSION/$ASSET_NAME"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
TMP_FILE="$TMP_DIR/$ASSET_NAME"

echo "Downloading ClickHouse $VERSION from $DOWNLOAD_URL ..."
curl -fL "$DOWNLOAD_URL" -o "$TMP_FILE"

case "$ASSET_TYPE" in
  binary)
    chmod +x "$TMP_FILE"
    SOURCE_BINARY="$TMP_FILE"
    ;;
  tar)
    if ! command -v tar >/dev/null 2>&1; then
      echo "tar is required to unpack $ASSET_NAME" >&2
      exit 1
    fi
    tar -xzf "$TMP_FILE" -C "$TMP_DIR"
    SOURCE_BINARY="$TMP_DIR/usr/bin/clickhouse"
    if [[ ! -f "$SOURCE_BINARY" ]]; then
      echo "Failed to locate clickhouse inside the extracted archive." >&2
      exit 1
    fi
    chmod +x "$SOURCE_BINARY"
    ;;
esac

mkdir -p "$INSTALL_DIR"
TARGET_PATH="$INSTALL_DIR/$BINARY_NAME"

if [[ -e "$TARGET_PATH" && "$FORCE" != "true" ]]; then
  echo "Target $TARGET_PATH already exists. Use --force to overwrite." >&2
  exit 1
fi

install -m 0755 "$SOURCE_BINARY" "$TARGET_PATH"

echo "ClickHouse installed to $TARGET_PATH"
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo "Reminder: add $INSTALL_DIR to your PATH to use the binary." >&2
fi

"$TARGET_PATH" --version || true
