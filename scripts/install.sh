#!/usr/bin/env bash
# Install binary, launch agent, and seed default config.
set -euo pipefail
cd "$(dirname "$0")/.."

sudo install -m 0755 custos /usr/local/bin/custos

CFG="$HOME/.config/custos"
mkdir -p "$CFG"
[ -f "$CFG/config.json" ] || cp config.example.json "$CFG/config.json"

PLIST="$HOME/Library/LaunchAgents/com.zachrielforever.custos.plist"
cp deploy/com.zachrielforever.custos.plist "$PLIST"
launchctl bootout "gui/$(id -u)/com.zachrielforever.custos" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

if grep -q "PASTE_FROM_GEN_SECRET" "$CFG/config.json" 2>/dev/null; then
    echo "no unlock secret configured — opening setup window"
    /usr/local/bin/custos setup
fi

echo "installed. Grant Accessibility + Input Monitoring to /usr/local/bin/custos,"
echo "then log out and back in."