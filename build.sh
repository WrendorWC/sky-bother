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

  # macOS attaches com.apple.provenance to executables on its own — not an
  # iCloud artefact, and present on the DerivedData copy too, so building
  # outside iCloud doesn't avoid it. It doesn't break the signature, but
  # `codesign --verify --deep --strict` rejects the bundle for carrying it
  # ("resource fork, Finder information, or similar detritus not allowed"),
  # which looks exactly like a signing failure. Strip it so a strict verify
  # passes. Anything that copies the app later can pick it up again.
  xattr -cr "build/$(basename "$app")"

  echo
  echo "Built: $PWD/build/$(basename "$app")"
  echo "Run it with:  open \"build/$(basename "$app")\""
done
