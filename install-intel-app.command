#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

chmod +x "${SCRIPT_DIR}"/scripts/*.sh
exec "${SCRIPT_DIR}/scripts/install-built-app.sh" "$@"
