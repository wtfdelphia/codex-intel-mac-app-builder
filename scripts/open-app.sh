#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

PREFERRED_APP="${1:-/Applications/Codex Intel.app}"
FALLBACK_APP="${DIST_DIR}/Codex Intel.app"

require_macos
require_cmd open

if [[ -d "${PREFERRED_APP}" ]]; then
  log "Opening installed app: ${PREFERRED_APP}"
  open "${PREFERRED_APP}"
  exit 0
fi

if [[ -d "${FALLBACK_APP}" ]]; then
  warn "Installed app not found. Opening the built app from dist instead."
  open "${FALLBACK_APP}"
  exit 0
fi

fail "No app bundle found. Build the app first, then install it."
