#!/usr/bin/env bash
# Install binary, launch agent, and default config.
set -euo pipefail

sudo install -m 0755 custos /usr/local/bin/custos

CFG="$HOME/.config/custos"
mkdir -p "$CFG"
[ -f "$CFG/config.json" ] || cp config.example.json "$CFG/config.json"

PLIST="$HOME/Library/LaunchAgents/com.zachrielforever.custos.plist"
cp deploy/com.zachrielforever.custos.plist "$PLIST"
if ! launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null; then
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
fi
echo "installed. Now grant Accessibility + Input Monitoring to /usr/local/bin/custos,"
echo "then log out and back in."