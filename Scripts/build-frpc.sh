#!/bin/bash
set -e

FRP_VERSION="${FRP_VERSION:-v0.70.0}"
OUTPUT_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/MacOS"

echo "Building frpc ${FRP_VERSION} universal binary..."

# Clone or update frp
cd /tmp
if [ -d "frp" ]; then
    cd frp
    git fetch
    git checkout "$FRP_VERSION"
else
    git clone --branch "$FRP_VERSION" --depth 1 https://github.com/fatedier/frp.git
    cd frp
fi

# Build for arm64
echo "Building for arm64..."
GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build -o frpc_arm64 ./cmd/frpc

# Build for x86_64
echo "Building for x86_64..."
GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 go build -o frpc_amd64 ./cmd/frpc

# Create universal binary
echo "Creating universal binary..."
lipo -create -output frpc frpc_arm64 frpc_amd64

# Copy to output
mkdir -p "$OUTPUT_DIR"
cp frpc "$OUTPUT_DIR/frpc"
chmod +x "$OUTPUT_DIR/frpc"

echo "Universal frpc built at $OUTPUT_DIR/frpc"
