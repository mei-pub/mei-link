#!/bin/bash
set -e

echo "=== Meilink Cross-Platform Build ==="

VERSION="${1:-1.1.0}"
BUILD_DIR="build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# The executable entry point is the root package (main.go imports cmd/meilink).
# NOTE: building ./cmd/meilink directly produces an archive, not a binary,
# because that package is `package meilink` (no func main).
echo "Building for $(go env GOOS)/$(go env GOARCH)..."
CGO_ENABLED=0 go build -ldflags "-X main.version=$VERSION" -o "$BUILD_DIR/meilink" .

echo "Binary: $BUILD_DIR/meilink"
echo ""
echo "Cross-compile examples:"
echo "  GOOS=windows GOARCH=amd64 go build -o meilink-windows-amd64.exe ."
echo "  GOOS=linux   GOARCH=arm64 go build -o meilink-linux-arm64    ."
echo "  GOOS=darwin  GOARCH=amd64 go build -o meilink-darwin-amd64   ."
echo "  GOOS=darwin  GOARCH=arm64 go build -o meilink-darwin-arm64   ."

# Also build the setup wizard (its own package main).
echo ""
echo "Building setup wizard..."
CGO_ENABLED=0 go build -ldflags "-X main.version=$VERSION" -o "$BUILD_DIR/meilink-setup" ./cmd/meilink-setup
echo "Setup wizard: $BUILD_DIR/meilink-setup"
