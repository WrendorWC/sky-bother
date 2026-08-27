#!/bin/bash
# Builds SkyBother and drops the .app in ./build. Requires Xcode command line
# tools; no Apple Developer account needed (the app is ad-hoc signed).
set -euo pipefail

CONFIGURATION="${1:-Release}"

xcodebuild \
  -project SkyBother.xcodeproj \
  -scheme SkyBother \
  -configuration "$CONFIGURATION" \
  -derivedDataPath build/DerivedData \
  CONFIGURATION_BUILD_DIR="$PWD/build" \
  build

echo
echo "Built: $PWD/build/SkyBother.app"
echo "Run it with:  open build/SkyBother.app"
