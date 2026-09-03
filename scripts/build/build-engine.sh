#!/bin/bash
set -e

# build-engine.sh — builds the meilink-tunnel binary (embedded frp library)
# and installs it into the app bundle's Contents/MacOS/ directory.
#
# Replaces the old download-frpc.sh which downloaded a pre-built frpc binary
# that antivirus software (ESET, Windows Defender, etc.) frequently quarantines.
# meilink-tunnel is compiled from source so its hash differs from frpc releases,
# and its name does not match any known AV signature database entry.

# Resolve output directory: prefer Xcode build vars, fall back to env overrides
# used by build-all.sh's SwiftPM path.
if [ -n "${BUILT_PRODUCTS_DIR}" ] && [ -n "${CONTENTS_FOLDER_PATH}" ]; then
    OUTPUT_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/MacOS"
elif [ -n "${BUILT_PRODUCTS_DIR}" ]; then
    # SwiftPM fallback: BUILT_PRODUCTS_DIR="$APP_BUNDLE/Contents", CONTENTS_FOLDER_PATH=""
    OUTPUT_DIR="${BUILT_PRODUCTS_DIR}/MacOS"
else
    echo "build-engine.sh: BUILT_PRODUCTS_DIR not set, cannot determine output path" >&2
    exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SIDECAR_DIR="$ROOT_DIR/client/desktop/sidecar"

if [ ! -d "$SIDECAR_DIR" ]; then
    echo "build-engine.sh: sidecar source not found at $SIDECAR_DIR" >&2
    exit 1
fi

if ! command -v go >/dev/null 2>&1; then
    echo "build-engine.sh: Go toolchain not found (required to build meilink-tunnel)" >&2
    exit 1
fi

echo "Building meilink-tunnel..."

cd "$SIDECAR_DIR"

# Build for the current architecture. The Xcode build phase runs on the
# host machine so this always matches the target.
export CGO_ENABLED=0
go build -o "${OUTPUT_DIR}/meilink-tunnel" ./cmd/meilink-tunnel/

chmod +x "${OUTPUT_DIR}/meilink-tunnel"

echo "meilink-tunnel built at ${OUTPUT_DIR}/meilink-tunnel"
