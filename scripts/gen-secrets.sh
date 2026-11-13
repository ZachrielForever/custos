#!/usr/bin/env bash
# Generate the Tier 4 unlock secret (salted SHA-512).
# Paste both printed values into ~/.config/custos/config.json.
set -euo pipefail

read -rsp "Custos unlock secret: " SECRET; echo
read -rsp "Confirm: " CONFIRM; echo
[ "${SECRET}" = "${CONFIRM}" ] || { echo "mismatch, aborting"; exit 1; }

SALT=$(openssl rand -hex 16)
HASH=$(printf '%s%s' "${SALT}" "${SECRET}" | shasum -a 512 | awk '{print $1}')

echo "paste into config.json:"
echo "\"unlock_secret_salt\": \"${SALT}\","
echo "\"unlock_secret_hash\": \"${HASH}\""