#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TARGET_APP_PATH="${1:-/Applications/Codex Intel.app}"
SOURCE_APP_PATH="${DIST_DIR}/Codex Intel.app"

require_macos
require_cmd ditto
require_cmd xattr

[[ -d "${SOURCE_APP_PATH}" ]] || fail "Built app not found. Run ./scripts/build.sh first."

log "Installing rebuilt Codex app"
log "Source app: ${SOURCE_APP_PATH}"
log "Target app: ${TARGET_APP_PATH}"

mkdir -p "$(dirname "${TARGET_APP_PATH}")"
rm -rf "${TARGET_APP_PATH}"
ditto "${SOURCE_APP_PATH}" "${TARGET_APP_PATH}"
xattr -cr "${TARGET_APP_PATH}" || true

log "Install complete"
log "Open it with: open \"${TARGET_APP_PATH}\""
