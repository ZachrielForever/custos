#!/usr/bin/env bash
# One-shot compile. Run on macOS with Xcode CLT installed.
set -euo pipefail
cd "$(dirname "$0")/.."

swiftc -O Sources/*.swift -o custos
echo "built $(pwd)/custos"