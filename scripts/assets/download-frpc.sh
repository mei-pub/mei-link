#!/bin/bash
set -e

FRP_VERSION="${FRP_VERSION:-v0.70.0}"
OUTPUT_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/MacOS"

echo "Downloading frpc ${FRP_VERSION}..."

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/frp_${FRP_VERSION#v}_darwin_arm64.tar.gz"
elif [ "$ARCH" = "x86_64" ]; then
    DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/frp_${FRP_VERSION#v}_darwin_amd64.tar.gz"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# Download and extract. Write the archive to a temp file first: when bsdtar
# reads from a pipe it can silently fail to apply --strip-components with a
# member pattern (and with no pipefail the curl exit code masks the failure),
# leaving the binary missing while the script still reports success.
#
# The binary is written straight to frpc.exe via --to-stdout so it never exists
# under the bare name "frpc": some endpoint-security agents delete newly created
# unsigned files named exactly "frpc". frpc.exe also matches the name the
# desktop app bundles, so the two clients share the convention.
mkdir -p "$OUTPUT_DIR"
TARBALL="$OUTPUT_DIR/frp-${FRP_VERSION}.tar.gz"
curl -L "$DOWNLOAD_URL" -o "$TARBALL"
tar xzf "$TARBALL" --to-stdout "*/frpc" > "$OUTPUT_DIR/frpc.exe"
chmod +x "$OUTPUT_DIR/frpc.exe"
rm -f "$TARBALL"

echo "frpc installed to $OUTPUT_DIR/frpc.exe"
