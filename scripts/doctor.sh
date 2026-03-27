#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

APP_PATH="/Applications/Codex Intel.app"
BUILD_INFO_FILE="${DIST_DIR}/build-info.txt"

check_ok() {
  printf "[ok] %s\n" "$1"
}

check_warn() {
  printf "[warn] %s\n" "$1"
}

check_cmd() {
  local name="$1"

  if command -v "${name}" >/dev/null 2>&1; then
    check_ok "${name} available"
  else
    check_warn "${name} missing"
  fi
}

check_file() {
  local path="$1"
  local label="$2"

  if [[ -e "${path}" ]]; then
    check_ok "${label}: ${path}"
  else
    check_warn "${label}: ${path}"
  fi
}

require_macos

printf "Codex Intel Mac App Builder Doctor\n"
printf "System: %s %s\n" "$(uname -s)" "$(uname -r)"
printf "Arch: %s\n\n" "$(uname -m)"

if [[ "$(uname -m)" == "x86_64" ]]; then
  check_ok "Intel Mac detected"
else
  check_warn "Non-Intel architecture detected"
fi

for cmd in bash hdiutil ditto npm npx node python3 codesign xattr file plutil find install xcode-select xcrun clang clang++; do
  check_cmd "${cmd}"
done

printf "\n"
if [[ -n "$(xcode_developer_dir)" ]]; then
  check_ok "Active developer dir: $(xcode_developer_dir)"
else
  check_warn "Active developer dir is not configured"
fi

if [[ -n "$(macos_sdk_path)" ]]; then
  check_ok "macOS SDK: $(macos_sdk_path)"
else
  check_warn "macOS SDK path is not available"
fi

printf "\n"
check_file "${PROJECT_DIR}/Codex.dmg" "Official DMG at project root"
check_file "${DIST_DIR}/Codex Intel.app" "Built app"
check_file "${DIST_DIR}/CodexAppMacIntel.dmg" "Built DMG"
check_file "${APP_PATH}" "Installed app"
check_file "${BUILD_INFO_FILE}" "Build info"

if [[ -f "${BUILD_INFO_FILE}" ]]; then
  printf "\nRecent build info:\n"
  cat "${BUILD_INFO_FILE}"
fi
