#!/usr/bin/env bash
# One-shot compile. Run on macOS with Xcode CLT installed.
set -euo pipefail

swiftc -O Sources/*.swift -o custos
echo "built ./custos"