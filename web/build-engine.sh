#!/bin/zsh
# Builds web/public/engine.wasm from the Mac app's own Swift (see engine/Package.swift).
# Needs the swift.org 6.4.0 toolchain + its Wasm SDK, and binaryen (wasm-opt):
#   https://www.swift.org/install/macos/  →  swift sdk install …swift-6.4.0-RELEASE_wasm…
#   brew install binaryen
# The built engine.wasm is checked in, since Cloudflare's builders have no Swift.
set -euo pipefail
cd "${0:A:h}/engine"

TOOLCHAIN=~/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain
SDK=swift-6.4.0-RELEASE_wasm
SDK_LIB=$(echo ~/Library/org.swift.swiftpm/swift-sdks/$SDK.artifactbundle/$SDK/wasm32-unknown-wasip1/swift.xctoolchain/usr/lib/swift_static/wasi)
export TOOLCHAINS=$(plutil -extract CFBundleIdentifier raw $TOOLCHAIN/Info.plist)

# 1. ICU data trimmed to what the engine uses.
mkdir -p .build/icu
(cd .build/icu && $TOOLCHAIN/usr/bin/llvm-ar x $SDK_LIB/lib_FoundationICU.a icu_packaged_data.cpp.obj)
python3 Scripts/slim_icu.py .build/icu/icu_packaged_data.cpp.obj Sources/ICUDataSlim/icudt_slim.c

# 2. Engine → wasm, plus the native twin used by the parity check.
swift build --swift-sdk $SDK -c release --product engine-wasm
swift build --product engine-cli

# 3. Shrink.
mkdir -p ../public
wasm-opt -Oz --strip-debug --strip-producers --enable-bulk-memory --enable-sign-ext \
    --enable-nontrapping-float-to-int --enable-mutable-globals \
    .build/out/Products/Release-webassembly-wasm32/engine-wasm.wasm -o ../public/engine.wasm
cp ../../SkyBother/Catalog/ExtendedCatalog.json ../public/catalog-extended.json
ls -l ../public/engine.wasm | awk '{printf "engine.wasm: %.1f MB, ", $5/1e6}'
gzip -9 -c ../public/engine.wasm | wc -c | awk '{printf "%.1f MB gzipped\n", $1/1e6}'
