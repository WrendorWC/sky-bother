#!/bin/bash
# Builds SkyBother and drops the .app in ./build. Requires Xcode command line
# tools; no Apple Developer account needed (the app is ad-hoc signed).
set -euo pipefail

CONFIGURATION="${1:-Release}"

# Build outside the project folder, then copy the finished app back. If the
# project lives somewhere iCloud syncs (Desktop/Documents), iCloud tags files
# there with extended attributes, and codesign refuses to sign a bundle
# carrying them ("resource fork, Finder information, or similar detritus not
# allowed"). Once signed, the app can live anywhere.
WORK_DIR="$HOME/Library/Developer/Xcode/DerivedData/SkyBother-build"

xcodebuild \
  -project SkyBother.xcodeproj \
  -scheme SkyBother \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$WORK_DIR" \
  CONFIGURATION_BUILD_DIR="$WORK_DIR/Products" \
  build

mkdir -p build
for app in "$WORK_DIR/Products"/*.app; do
  rm -rf "build/$(basename "$app")"
  ditto "$app" "build/$(basename "$app")"

  # Clears extended attributes off the copy. Worth doing for the iCloud tags
  # the note above is about, which is what actually blocks signing.
  #
  # It does NOT durably clear com.apple.provenance: macOS attaches that to
  # executables by itself, re-applies it on copy and again on launch, and it
  # is on the DerivedData build too, so building outside iCloud doesn't avoid
  # it either. It's harmless — the bundle verifies, strictly and deeply, with
  # it present — so nothing here needs to chase it.
  xattr -cr "build/$(basename "$app")"

  echo
  echo "Built: $PWD/build/$(basename "$app")"
  echo "Run it with:  open \"build/$(basename "$app")\""
done
