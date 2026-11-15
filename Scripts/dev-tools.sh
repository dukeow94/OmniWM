#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$ROOT_DIR/.cache/flake-tools"
BIN_DIR="$TOOLS_DIR/bin"
DOWNLOAD_DIR="$ROOT_DIR/.cache/dev-tool-downloads"
FRAMEWORK_DIR="$ROOT_DIR/Frameworks/GhosttyKit.xcframework"
WORK_DIR=""
source "$ROOT_DIR/Scripts/dev-tools.env"

fail() {
  echo "dev-tools: $*" >&2
  exit 1
}

cleanup() {
  if [ -n "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}

has_digest() {
  [ -f "$1" ] && [ "$(shasum -a 256 "$1" | awk '{print $1}')" = "$2" ]
}

download() {
  local url="$1" digest="$2" destination="$DOWNLOAD_DIR/$2"
  if ! has_digest "$destination" "$digest"; then
    echo "Downloading $url" >&2
    curl --fail --location --silent --show-error --connect-timeout 15 --max-time 600 \
      "$url" --output "$WORK_DIR/download" || fail "Download failed: $url"
    has_digest "$WORK_DIR/download" "$digest" || fail "Downloaded archive checksum mismatch: $url"
    mv -f "$WORK_DIR/download" "$destination"
  fi
  printf '%s\n' "$destination"
}

tool_version() {
  case "$1" in
    swiftformat) "$2" --version ;;
    swiftlint) "$2" version ;;
    fish) "$2" --version | awk '{print $3}' ;;
    nu) "$2" --version ;;
  esac
}

install_tool() {
  local tool="$1" expected="$2" url="$3" digest="$4" archive actual staging executable
  if actual="$(tool_version "$tool" "$BIN_DIR/$tool" 2>/dev/null)" && [ "$actual" = "$expected" ]; then
    echo "$tool: $actual (reused)"
    return
  fi
  archive="$(download "$url" "$digest")"
  staging="$WORK_DIR/$tool"
  mkdir -p "$staging"
  case "$tool" in
    nu)
      tar -xzf "$archive" -C "$staging"
      executable="$staging/nu-$expected-aarch64-apple-darwin/nu"
      ;;
    fish)
      ditto -x -k "$archive" "$staging"
      executable="$staging/fish-$expected.app/Contents/Resources/base/usr/local/bin/fish"
      ;;
    *)
      ditto -x -k "$archive" "$staging"
      executable="$staging/$tool"
      ;;
  esac
  [ -f "$executable" ] || fail "$tool archive did not contain the expected executable."
  chmod 755 "$executable"
  actual="$(tool_version "$tool" "$executable")"
  [ "$actual" = "$expected" ] || fail "$tool archive reports $actual; expected $expected."
  if [ "$tool" = fish ]; then
    mkdir -p "$TOOLS_DIR/libexec"
    local app="$TOOLS_DIR/libexec/fish-$expected.app"
    [ ! -e "$app" ] || fail "$app already exists but its executable was not reusable; inspect it before retrying."
    mv "$staging/fish-$expected.app" "$app"
    ln -sfn "../libexec/fish-$expected.app/Contents/Resources/base/usr/local/bin/fish" "$BIN_DIR/fish"
  else
    mv -f "$executable" "$BIN_DIR/$tool"
  fi
  echo "$tool: $actual (installed)"
}

verify_framework() {
  [ -f "$FRAMEWORK_DIR/Info.plist" ] && "$ROOT_DIR/Scripts/ghostty-preflight.sh" verify
}

install_framework() {
  local archive staging="$WORK_DIR/ghostty"
  if [ -e "$FRAMEWORK_DIR" ] || [ -L "$FRAMEWORK_DIR" ]; then
    verify_framework || fail "Existing GhosttyKit does not match this checkout; it was preserved. Move it aside before retrying."
    return
  fi
  archive="$(download "$OMNIWM_GHOSTTY_DOWNLOAD_URL" "$OMNIWM_GHOSTTY_ZIP_SHA256")"
  mkdir -p "$staging/Frameworks" "$staging/Scripts"
  ditto -x -k "$archive" "$staging/Frameworks"
  [ -f "$staging/Frameworks/GhosttyKit.xcframework/Info.plist" ] || fail "GhosttyKit archive is incomplete."
  cp "$ROOT_DIR/Scripts/ghostty-preflight.sh" "$ROOT_DIR/Scripts/build-metadata.env" "$staging/Scripts/"
  "$staging/Scripts/ghostty-preflight.sh" verify
  mkdir -p "$ROOT_DIR/Frameworks"
  mv -n "$staging/Frameworks/GhosttyKit.xcframework" "$ROOT_DIR/Frameworks/"
  verify_framework || fail "GhosttyKit verification failed; any existing framework was preserved."
}

MODE="${1:-setup}"
case "$MODE" in
  setup|setup-tools)
    [ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || fail "Use a native Apple Silicon macOS terminal."
    mkdir -p "$BIN_DIR" "$DOWNLOAD_DIR"
    WORK_DIR="$(mktemp -d "$TOOLS_DIR/setup.XXXXXX")"
    trap cleanup EXIT
    install_tool swiftformat "$SWIFTFORMAT_VERSION" "$OMNIWM_SWIFTFORMAT_DOWNLOAD_URL" "$OMNIWM_SWIFTFORMAT_ZIP_SHA256"
    install_tool swiftlint "$SWIFTLINT_VERSION" "$OMNIWM_SWIFTLINT_DOWNLOAD_URL" "$OMNIWM_SWIFTLINT_ZIP_SHA256"
    install_tool fish "$FISH_VERSION" "$OMNIWM_FISH_DOWNLOAD_URL" "$OMNIWM_FISH_ZIP_SHA256"
    install_tool nu "$NUSHELL_VERSION" "$OMNIWM_NUSHELL_DOWNLOAD_URL" "$OMNIWM_NUSHELL_TAR_SHA256"
    if [ "$MODE" = setup ]; then
      install_framework
    fi
    ;;
  *)
    echo "Usage: Scripts/dev-tools.sh [setup|setup-tools]" >&2
    exit 64
    ;;
esac
