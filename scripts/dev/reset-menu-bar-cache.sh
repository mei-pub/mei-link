#!/usr/bin/env bash
set -euo pipefail

DOMAINS=(
  "com.meilink.app"
  "pub.mei.meilink"
)

KEYS=(
  "NSStatusItem Visible Item-0"
  "NSStatusItem VisibleCC Item-0"
  "NSStatusItem Visible Meilink.StatusBarItem.v2"
  "NSStatusItem VisibleCC Meilink.StatusBarItem.v2"
  "NSStatusItem Visible Meilink.StatusBarItem.v3"
  "NSStatusItem VisibleCC Meilink.StatusBarItem.v3"
  "NSStatusItem Visible Meilink.StatusBarItem.v4"
  "NSStatusItem VisibleCC Meilink.StatusBarItem.v4"
)

echo "Resetting Meilink menu bar cache..."

for domain in "${DOMAINS[@]}"; do
  for key in "${KEYS[@]}"; do
    defaults delete "$domain" "$key" >/dev/null 2>&1 || true
  done
done

echo "Done."
echo "If the old item is still misplaced, quit Meilink and run:"
echo "  killall ControlCenter"
