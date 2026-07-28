#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
swiftc \
  -O \
  -whole-module-optimization \
  Sources/*.swift \
  -o build/kuller
echo "Built build/kuller"
