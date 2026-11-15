#!/usr/bin/env bash
# One-shot compile. Run on macOS with Xcode CLT installed.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="custos-dev"

swiftc -O Sources/*.swift -o custos

if security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" custos
    echo "built $(pwd)/custos (signed: $IDENTITY)"
else
    echo "WARNING: identity '$IDENTITY' missing — binary is unsigned."
    echo "Run scripts/make-identity.sh once, or re-grant Input Monitoring"
    echo "after every rebuild while unsigned."
    echo "built $(pwd)/custos (unsigned)"
fi