#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/Scripts/lib/frpc-archive.sh"

if [ -n "${MEILINK_TEST_TAR:-}" ]; then
    tar() {
        local argument
        local -a arguments=()
        for argument in "$@"; do
            if [[ "$argument" = /* ]] && [ -e "$argument" ]; then
                arguments+=("$(wslpath -w "$argument")")
            else
                arguments+=("$argument")
            fi
        done
        "$MEILINK_TEST_TAR" "${arguments[@]}"
    }
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ARCHIVE_ROOT="frp_0.70.0_darwin_arm64"
mkdir -p "$TMP_DIR/$ARCHIVE_ROOT"
printf 'frpc-test-payload\n' > "$TMP_DIR/$ARCHIVE_ROOT/frpc"
printf 'not-the-binary\n' > "$TMP_DIR/$ARCHIVE_ROOT/frpc.sha256"
tar -czf "$TMP_DIR/frpc.tar.gz" -C "$TMP_DIR" "$ARCHIVE_ROOT"

extract_tar_member "$TMP_DIR/frpc.tar.gz" "frpc" > "$TMP_DIR/extracted-frpc"
cmp "$TMP_DIR/$ARCHIVE_ROOT/frpc" "$TMP_DIR/extracted-frpc"

echo "PASS: extracts the frpc archive member without GNU tar wildcards"
