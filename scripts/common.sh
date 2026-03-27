#!/usr/bin/env bash

PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${PROJECT_DIR}/dist"
TMP_DIR="${PROJECT_DIR}/.tmp"
LOG_DIR="${PROJECT_DIR}/logs"

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

log() {
  printf "[%s] %s\n" "$(timestamp)" "$*"
}

warn() {
  printf "[%s] WARN: %s\n" "$(timestamp)" "$*" >&2
}

fail() {
  printf "[%s] ERROR: %s\n" "$(timestamp)" "$*" >&2
  exit 1
}

ensure_dir() {
  mkdir -p "$1"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "This project only runs on macOS."
}

xcode_developer_dir() {
  xcode-select --print-path 2>/dev/null || true
}

macos_sdk_path() {
  xcrun --sdk macosx --show-sdk-path 2>/dev/null || true
}

ensure_macos_toolchain() {
  local developer_dir
  local sdk_path

  require_cmd xcode-select
  require_cmd xcrun
  require_cmd clang
  require_cmd clang++
  require_cmd python3

  developer_dir="$(xcode_developer_dir)"
  [[ -n "${developer_dir}" && -d "${developer_dir}" ]] || \
    fail "No active Xcode developer directory. Run xcode-select --install first."

  sdk_path="$(macos_sdk_path)"
  [[ -n "${sdk_path}" && -d "${sdk_path}" ]] || \
    fail "Could not locate the macOS SDK. Run xcode-select --install or fix xcode-select --switch."
}

append_env_flag() {
  local current_value="$1"
  local extra_value="$2"

  if [[ -n "${current_value}" ]]; then
    printf "%s %s\n" "${current_value}" "${extra_value}"
  else
    printf "%s\n" "${extra_value}"
  fi
}

export_macos_toolchain() {
  local sdk_path

  ensure_macos_toolchain
  sdk_path="$(macos_sdk_path)"

  export SDKROOT="${SDKROOT:-${sdk_path}}"
  export CC="${CC:-$(xcrun --sdk macosx --find clang)}"
  export CXX="${CXX:-$(xcrun --sdk macosx --find clang++)}"
  export CPPFLAGS="$(append_env_flag "${CPPFLAGS:-}" "-isysroot ${SDKROOT}")"
  export CFLAGS="$(append_env_flag "${CFLAGS:-}" "-isysroot ${SDKROOT}")"
  export CXXFLAGS="$(append_env_flag "${CXXFLAGS:-}" "-isysroot ${SDKROOT} -stdlib=libc++")"
  export LDFLAGS="$(append_env_flag "${LDFLAGS:-}" "-isysroot ${SDKROOT}")"
  export npm_config_python="${npm_config_python:-$(command -v python3)}"
}

warn_if_not_intel() {
  local arch
  arch="$(uname -m)"

  if [[ "${arch}" != "x86_64" ]]; then
    warn "Detected ${arch}. This workflow is designed for Intel Macs and may not behave as expected."
  fi
}

plist_get() {
  local key="$1"
  local file="$2"
  /usr/libexec/PlistBuddy -c "Print :${key}" "${file}" 2>/dev/null || \
    plutil -extract "${key}" raw -o - "${file}" 2>/dev/null || true
}

absolute_path() {
  local input_path="$1"
  local input_dir

  input_dir="$(cd "$(dirname "${input_path}")" && pwd)"
  printf "%s/%s\n" "${input_dir}" "$(basename "${input_path}")"
}

first_match() {
  local root="$1"
  local pattern="$2"

  find "${root}" -type f -path "${pattern}" | sort | head -n 1
}
