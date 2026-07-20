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

# Download and extract
mkdir -p "$OUTPUT_DIR"
curl -L "$DOWNLOAD_URL" | tar xz -C "$OUTPUT_DIR" --strip-components=1 "*/frpc"
chmod +x "$OUTPUT_DIR/frpc"

echo "frpc installed to $OUTPUT_DIR/frpc"
