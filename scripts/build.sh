#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

RUN_ID="$(date +%Y%m%d_%H%M%S)"
WORK_DIR="${TMP_DIR}/build_${RUN_ID}"
SOURCE_MOUNT="${WORK_DIR}/source-mount"
DMG_ROOT="${WORK_DIR}/dmg-root"
BUILD_PROJECT="${WORK_DIR}/build-project"
ASAR_META_DIR="${WORK_DIR}/asar-meta"
LOG_FILE="${LOG_DIR}/build_${RUN_ID}.log"
DIST_APP="${DIST_DIR}/Codex Intel.app"
DIST_DMG="${DIST_DIR}/CodexAppMacIntel.dmg"
BUILD_INFO_FILE="${DIST_DIR}/build-info.txt"

ATTACHED_BY_SCRIPT=0
KEEP_WORKDIR="${CODEX_KEEP_WORKDIR:-0}"
INPUT_DMG_ARG="${1:-}"
VERSION_OVERRIDE="${CODEX_PACKAGE_VERSION:-${2:-}}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/build.sh [path/to/Codex.dmg] [codex_package_version]

Behavior:
  - reads an official Codex.dmg
  - rebuilds the app around an x86_64 Electron runtime
  - rebuilds native modules for x86_64
  - outputs dist/Codex Intel.app and dist/CodexAppMacIntel.dmg

Overrides:
  CODEX_PACKAGE_VERSION=0.111.0
  CODEX_KEEP_WORKDIR=1
EOF
}

cleanup() {
  local exit_code=$?

  if [[ "${ATTACHED_BY_SCRIPT}" -eq 1 && -d "${SOURCE_MOUNT}" ]]; then
    hdiutil detach "${SOURCE_MOUNT}" >/dev/null 2>&1 || \
      hdiutil detach -force "${SOURCE_MOUNT}" >/dev/null 2>&1 || true
  fi

  if [[ "${exit_code}" -eq 0 && "${KEEP_WORKDIR}" != "1" ]]; then
    rm -rf "${WORK_DIR}"
  elif [[ -d "${WORK_DIR}" ]]; then
    log "Work directory kept at: ${WORK_DIR}"
  fi
}
trap cleanup EXIT

extract_asar_file() {
  local asar_file="$1"
  local asar_path="$2"
  local output_path="$3"
  local output_dir
  local extracted_name

  output_dir="$(dirname "${output_path}")"
  extracted_name="$(basename "${asar_path}")"
  mkdir -p "${output_dir}"

  (
    cd "${output_dir}"
    rm -f "${extracted_name}"
    npx --yes @electron/asar extract-file "${asar_file}" "${asar_path}"
  )

  [[ -f "${output_dir}/${extracted_name}" ]] || fail "Failed to extract ${asar_path} from app.asar"
  mv "${output_dir}/${extracted_name}" "${output_path}"
}

resolve_input_dmg() {
  local explicit_input="${1:-}"
  local candidate
  local found_dmgs=()

  if [[ -n "${explicit_input}" ]]; then
    absolute_path "${explicit_input}"
    return 0
  fi

  for candidate in \
    "${PROJECT_DIR}/Codex.dmg" \
    "$(cd "${PROJECT_DIR}/.." && pwd)/Codex.dmg"; do
    if [[ -f "${candidate}" ]]; then
      printf "%s\n" "${candidate}"
      return 0
    fi
  done

  while IFS= read -r candidate; do
    found_dmgs+=("${candidate}")
  done < <(find "$(cd "${PROJECT_DIR}/.." && pwd)" -maxdepth 1 -type f -name "*.dmg" ! -name "CodexAppMacIntel.dmg" | sort)

  if [[ "${#found_dmgs[@]}" -eq 1 ]]; then
    printf "%s\n" "${found_dmgs[0]}"
    return 0
  fi

  if [[ "${#found_dmgs[@]}" -gt 1 ]]; then
    printf "%s\n" "${found_dmgs[@]}"
    fail "Multiple DMGs found. Pass the official Codex.dmg path explicitly."
  fi

  fail "No official Codex.dmg found. Put it next to the project or pass an absolute path."
}

resolve_codex_package_version() {
  local app_dep_spec="$1"
  local app_package_version="$2"
  local bundle_version="$3"
  local candidate
  local candidates=()
  local resolved_version
  local fallback_tag
  local fallback_tags=()

  if [[ -n "${VERSION_OVERRIDE}" ]]; then
    candidates+=("${VERSION_OVERRIDE}")
  fi

  if [[ -n "${app_dep_spec}" ]]; then
    candidates+=("${app_dep_spec}")

    if [[ "${app_dep_spec}" == npm:@openai/codex@* ]]; then
      candidates+=("${app_dep_spec#npm:@openai/codex@}")
    fi
  fi

  if [[ -n "${app_package_version}" ]]; then
    candidates+=("${app_package_version}")
  fi

  if [[ -n "${bundle_version}" ]]; then
    candidates+=("${bundle_version}")
  fi

  for candidate in "${candidates[@]}"; do
    [[ -n "${candidate}" ]] || continue

    if resolved_version="$(npm view "@openai/codex@${candidate}" version 2>/dev/null | tail -n 1)"; then
      if [[ "${resolved_version}" =~ ^(.+)-(darwin|linux|win32)-(x64|arm64)$ ]]; then
        if npm view "@openai/codex@${BASH_REMATCH[1]}" version >/dev/null 2>&1; then
          printf "%s\n" "${BASH_REMATCH[1]}"
          return 0
        fi
      fi

      printf "%s\n" "${resolved_version}"
      return 0
    fi

    if [[ "${candidate}" =~ ^(.+)-(darwin|linux|win32)-(x64|arm64)$ ]]; then
      if resolved_version="$(npm view "@openai/codex@${BASH_REMATCH[1]}" version 2>/dev/null | tail -n 1)"; then
        printf "%s\n" "${resolved_version}"
        return 0
      fi
    fi
  done

  if [[ "${app_package_version}" == 0.1.* || "${bundle_version}" == 0.1.* ]]; then
    fallback_tags+=("native")
  fi
  fallback_tags+=("latest")

  for fallback_tag in "${fallback_tags[@]}"; do
    if resolved_version="$(npm view "@openai/codex@${fallback_tag}" version 2>/dev/null | tail -n 1)"; then
      if [[ "${resolved_version}" =~ ^(.+)-(darwin|linux|win32)-(x64|arm64)$ ]]; then
        if npm view "@openai/codex@${BASH_REMATCH[1]}" version >/dev/null 2>&1; then
          printf "%s\n" "${BASH_REMATCH[1]}"
          return 0
        fi
      fi

      printf "%s\n" "${resolved_version}"
      return 0
    fi
  done

  fail "Could not resolve a matching @openai/codex version. Pass it explicitly as the second argument or CODEX_PACKAGE_VERSION."
}

copy_node_pty_bin_artifacts() {
  local built_bin_root="$1"
  local target_bin_root="$2"
  local built_node
  local built_dir_name
  local target_node

  built_node="$(find "${built_bin_root}" -type f -name "node-pty.node" | grep "darwin-x64-" | sort | head -n 1 || true)"
  [[ -n "${built_node}" ]] || return 0

  built_dir_name="$(basename "$(dirname "${built_node}")")"
  mkdir -p "${target_bin_root}/${built_dir_name}"
  install -m 755 "${built_node}" "${target_bin_root}/${built_dir_name}/node-pty.node"

  while IFS= read -r target_node; do
    install -m 755 "${built_node}" "${target_node}"
  done < <(find "${target_bin_root}" -type f -name "node-pty.node" | sort)
}

assert_x86_64_binary() {
  local file_path="$1"
  local file_output

  [[ -f "${file_path}" ]] || fail "Expected binary not found: ${file_path}"
  file_output="$(file "${file_path}")"
  printf "%s\n" "${file_output}"
  [[ "${file_output}" == *"x86_64"* ]] || fail "Expected x86_64 binary: ${file_path}"
}

if [[ "${INPUT_DMG_ARG}" == "-h" || "${INPUT_DMG_ARG}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$#" -gt 2 ]]; then
  usage
  fail "Too many arguments."
fi

ensure_dir "${TMP_DIR}"
ensure_dir "${DIST_DIR}"
ensure_dir "${LOG_DIR}"
mkdir -p "${WORK_DIR}"
: > "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1

require_macos
warn_if_not_intel

for cmd in bash hdiutil ditto npm npx node python3 file codesign xattr plutil find install xcode-select xcrun clang clang++; do
  require_cmd "${cmd}"
done
ensure_macos_toolchain
export_macos_toolchain

INPUT_DMG="$(resolve_input_dmg "${INPUT_DMG_ARG}")"
[[ -f "${INPUT_DMG}" ]] || fail "Source DMG not found: ${INPUT_DMG}"

log "Starting Intel Codex app build"
log "Project dir: ${PROJECT_DIR}"
log "Source DMG: ${INPUT_DMG}"
log "Work dir: ${WORK_DIR}"
log "Log file: ${LOG_FILE}"
log "Active developer dir: $(xcode_developer_dir)"
log "macOS SDK: ${SDKROOT}"

mkdir -p "${SOURCE_MOUNT}"
if hdiutil attach -readonly -nobrowse -mountpoint "${SOURCE_MOUNT}" "${INPUT_DMG}" >/dev/null; then
  ATTACHED_BY_SCRIPT=1
else
  fail "Failed to mount the official Codex.dmg"
fi

SOURCE_APP="${SOURCE_MOUNT}/Codex.app"
[[ -d "${SOURCE_APP}" ]] || fail "Codex.app was not found inside the mounted DMG."

ORIGINAL_APP="${WORK_DIR}/CodexOriginal.app"
TARGET_APP="${WORK_DIR}/Codex Intel.app"

log "Copying source app bundle"
ditto "${SOURCE_APP}" "${ORIGINAL_APP}"

SOURCE_INFO_PLIST="${ORIGINAL_APP}/Contents/Info.plist"
FRAMEWORK_INFO="${ORIGINAL_APP}/Contents/Frameworks/Electron Framework.framework/Versions/A/Resources/Info.plist"
ASAR_FILE="${ORIGINAL_APP}/Contents/Resources/app.asar"

[[ -f "${SOURCE_INFO_PLIST}" ]] || fail "Missing source Info.plist"
[[ -f "${FRAMEWORK_INFO}" ]] || fail "Missing Electron framework Info.plist"
[[ -f "${ASAR_FILE}" ]] || fail "Missing app.asar"

ROOT_PKG="${ASAR_META_DIR}/root.package.json"
BS_PKG="${ASAR_META_DIR}/better-sqlite3.package.json"
NP_PKG="${ASAR_META_DIR}/node-pty.package.json"

log "Extracting app metadata from app.asar"
extract_asar_file "${ASAR_FILE}" "package.json" "${ROOT_PKG}"
extract_asar_file "${ASAR_FILE}" "node_modules/better-sqlite3/package.json" "${BS_PKG}"
extract_asar_file "${ASAR_FILE}" "node_modules/node-pty/package.json" "${NP_PKG}"

BUNDLE_VERSION="$(plist_get "CFBundleShortVersionString" "${SOURCE_INFO_PLIST}")"
ELECTRON_VERSION="$(plist_get "CFBundleVersion" "${FRAMEWORK_INFO}")"
APP_PACKAGE_VERSION="$(node -p "const pkg=require(process.argv[1]); pkg.version || ''" "${ROOT_PKG}")"
APP_CODEX_DEP_SPEC="$(node -p "const pkg=require(process.argv[1]); ((pkg.dependencies||{})['@openai/codex'] || (pkg.optionalDependencies||{})['@openai/codex'] || (pkg.devDependencies||{})['@openai/codex'] || '').toString()" "${ROOT_PKG}")"
BS_VERSION="$(node -p "const pkg=require(process.argv[1]); pkg.version || ''" "${BS_PKG}")"
NP_VERSION="$(node -p "const pkg=require(process.argv[1]); pkg.version || ''" "${NP_PKG}")"
CODEX_PACKAGE_VERSION="$(resolve_codex_package_version "${APP_CODEX_DEP_SPEC}" "${APP_PACKAGE_VERSION}" "${BUNDLE_VERSION}")"

[[ -n "${ELECTRON_VERSION}" ]] || fail "Could not detect the Electron version from the source app."
[[ -n "${BS_VERSION}" ]] || fail "Could not detect better-sqlite3 version."
[[ -n "${NP_VERSION}" ]] || fail "Could not detect node-pty version."

log "Detected bundle version: ${BUNDLE_VERSION:-unknown}"
log "Detected app package version: ${APP_PACKAGE_VERSION:-unknown}"
log "Detected app @openai/codex dependency spec: ${APP_CODEX_DEP_SPEC:-unknown}"
log "Resolved @openai/codex version: ${CODEX_PACKAGE_VERSION}"
log "Detected Electron version: ${ELECTRON_VERSION}"
log "Detected better-sqlite3 version: ${BS_VERSION}"
log "Detected node-pty version: ${NP_VERSION}"

mkdir -p "${BUILD_PROJECT}"
cat > "${BUILD_PROJECT}/package.json" <<EOF
{
  "name": "codex-intel-app-rebuild",
  "private": true,
  "version": "1.0.0",
  "dependencies": {
    "@openai/codex": "${CODEX_PACKAGE_VERSION}",
    "better-sqlite3": "${BS_VERSION}",
    "electron": "${ELECTRON_VERSION}",
    "node-pty": "${NP_VERSION}"
  },
  "devDependencies": {
    "@electron/rebuild": "4.0.3"
  }
}
EOF

log "Installing x64 runtime dependencies"
(
  cd "${BUILD_PROJECT}"
  npm_config_arch=x64 npm_config_platform=darwin npm install --no-audit --no-fund
)

log "Creating x64 Electron runtime shell"
ditto "${BUILD_PROJECT}/node_modules/electron/dist/Electron.app" "${TARGET_APP}"

log "Injecting Codex resources into x64 runtime"
rm -rf "${TARGET_APP}/Contents/Resources"
ditto "${ORIGINAL_APP}/Contents/Resources" "${TARGET_APP}/Contents/Resources"
cp "${SOURCE_INFO_PLIST}" "${TARGET_APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Electron" "${TARGET_APP}/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:ELECTRON_RENDERER_URL string app://-/index.html" "${TARGET_APP}/Contents/Info.plist" >/dev/null 2>&1 || \
  /usr/libexec/PlistBuddy -c "Set :LSEnvironment:ELECTRON_RENDERER_URL app://-/index.html" "${TARGET_APP}/Contents/Info.plist" >/dev/null

log "Rebuilding native modules for x86_64"
(
  cd "${BUILD_PROJECT}"
  npx --yes @electron/rebuild -f -w better-sqlite3,node-pty --arch=x64 --version "${ELECTRON_VERSION}" -m "${BUILD_PROJECT}"
)

TARGET_UNPACKED="${TARGET_APP}/Contents/Resources/app.asar.unpacked"
TARGET_NODE_PTY_BIN_ROOT="${TARGET_UNPACKED}/node_modules/node-pty/bin"

[[ -d "${TARGET_UNPACKED}" ]] || fail "app.asar.unpacked was not found after transplant."

log "Replacing rebuilt native binaries"
install -m 755 "${BUILD_PROJECT}/node_modules/better-sqlite3/build/Release/better_sqlite3.node" \
  "${TARGET_UNPACKED}/node_modules/better-sqlite3/build/Release/better_sqlite3.node"
install -m 755 "${BUILD_PROJECT}/node_modules/node-pty/build/Release/pty.node" \
  "${TARGET_UNPACKED}/node_modules/node-pty/build/Release/pty.node"
install -m 755 "${BUILD_PROJECT}/node_modules/node-pty/build/Release/spawn-helper" \
  "${TARGET_UNPACKED}/node_modules/node-pty/build/Release/spawn-helper"

if [[ -d "${TARGET_NODE_PTY_BIN_ROOT}" ]]; then
  copy_node_pty_bin_artifacts "${BUILD_PROJECT}/node_modules/node-pty/bin" "${TARGET_NODE_PTY_BIN_ROOT}"
fi

CLI_X64_BIN="$(first_match "${BUILD_PROJECT}/node_modules" "*/vendor/x86_64-apple-darwin/codex/codex")"
RG_X64_BIN="$(first_match "${BUILD_PROJECT}/node_modules" "*/vendor/x86_64-apple-darwin/path/rg")"

[[ -n "${CLI_X64_BIN}" ]] || fail "Could not locate the x64 Codex CLI binary in node_modules."
[[ -n "${RG_X64_BIN}" ]] || fail "Could not locate the x64 rg binary in node_modules."

log "Replacing bundled codex and rg binaries with x64 variants"
install -m 755 "${CLI_X64_BIN}" "${TARGET_APP}/Contents/Resources/codex"
if [[ -f "${TARGET_UNPACKED}/codex" ]]; then
  install -m 755 "${CLI_X64_BIN}" "${TARGET_UNPACKED}/codex"
fi
install -m 755 "${RG_X64_BIN}" "${TARGET_APP}/Contents/Resources/rg"

log "Disabling incompatible built-in updater addon"
rm -f "${TARGET_APP}/Contents/Resources/native/sparkle.node"
rm -f "${TARGET_UNPACKED}/native/sparkle.node"

log "Validating x86_64 outputs"
assert_x86_64_binary "${TARGET_APP}/Contents/MacOS/Electron"
assert_x86_64_binary "${TARGET_APP}/Contents/Resources/codex"
assert_x86_64_binary "${TARGET_APP}/Contents/Resources/rg"
assert_x86_64_binary "${TARGET_UNPACKED}/node_modules/better-sqlite3/build/Release/better_sqlite3.node"
assert_x86_64_binary "${TARGET_UNPACKED}/node_modules/node-pty/build/Release/pty.node"

log "Applying ad-hoc signature"
xattr -cr "${TARGET_APP}" || true
codesign --force --deep --sign - --timestamp=none "${TARGET_APP}"
codesign --verify --deep --strict "${TARGET_APP}"

log "Writing outputs"
rm -rf "${DIST_APP}"
rm -f "${DIST_DMG}" "${BUILD_INFO_FILE}"
ditto "${TARGET_APP}" "${DIST_APP}"

mkdir -p "${DMG_ROOT}"
ditto "${TARGET_APP}" "${DMG_ROOT}/Codex Intel.app"
ln -s /Applications "${DMG_ROOT}/Applications"
hdiutil create -volname "Codex Intel" -srcfolder "${DMG_ROOT}" -ov -format UDZO "${DIST_DMG}" >/dev/null

cat > "${BUILD_INFO_FILE}" <<EOF
Built at: $(timestamp)
Source DMG: ${INPUT_DMG}
Bundle version: ${BUNDLE_VERSION:-unknown}
App package version: ${APP_PACKAGE_VERSION:-unknown}
App @openai/codex dependency spec: ${APP_CODEX_DEP_SPEC:-unknown}
Resolved @openai/codex version: ${CODEX_PACKAGE_VERSION}
Electron version: ${ELECTRON_VERSION}
better-sqlite3 version: ${BS_VERSION}
node-pty version: ${NP_VERSION}
Output app: ${DIST_APP}
Output dmg: ${DIST_DMG}
Log file: ${LOG_FILE}
EOF

log "Build finished successfully"
log "Output app: ${DIST_APP}"
log "Output dmg: ${DIST_DMG}"
log "Build info: ${BUILD_INFO_FILE}"
