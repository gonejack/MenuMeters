#!/bin/bash
#
# Build MenuMeters with the Command Line Tools only (no Xcode installation).
#
#   ./build-clt.sh
#
# Produces a complete, ad-hoc-signed universal application bundle:
#
#   out/MenuMeters.app
#
# The bundle contains the Swift executable (arm64 + x86_64), Sparkle, the
# localized string tables, the disk icon sets, and the About text. Run it with
# `open out/MenuMeters.app`.
#
set -euo pipefail
cd "$(dirname "$0")"

SDK=$(xcrun --sdk macosx --show-sdk-path)
OUT=out
APP="$OUT/MenuMeters.app"
OBJ="$OUT/obj"
RES="$APP/Contents/Resources"
FRAMEWORKS="$APP/Contents/Frameworks"
DEPLOYMENT_TARGET=26.0

rm -rf "$OUT"
mkdir -p "$OBJ" "$APP/Contents/MacOS" "$RES" "$FRAMEWORKS"

SOURCES=(Sources/MenuMeters/*.swift)
COMMON_FLAGS=(
    -sdk "$SDK"
    -module-name MenuMeters
    -O -whole-module-optimization
    -Xlinker -rpath -Xlinker @loader_path/../Frameworks
)

# Sparkle is optional at compile time: without the framework the app still
# builds, but the update controls are hidden (the `#if canImport(Sparkle)`
# branches in the sources take care of that). Set NO_SPARKLE=1 to force a
# build without automatic updates.
if [ "${NO_SPARKLE:-0}" != "1" ] && [ -d Sparkle.framework ]; then
    COMMON_FLAGS+=(-F . -framework Sparkle)
    ditto Sparkle.framework "$FRAMEWORKS/Sparkle.framework"
else
    echo "note: building without automatic updates"
fi

for arch in arm64 x86_64; do
    echo "Compiling $arch..."
    xcrun swiftc "${COMMON_FLAGS[@]}" \
        -target "$arch-apple-macos$DEPLOYMENT_TARGET" \
        -o "$OBJ/MenuMeters-$arch" \
        "${SOURCES[@]}"
done

lipo -create "$OBJ/MenuMeters-arm64" "$OBJ/MenuMeters-x86_64" \
    -output "$APP/Contents/MacOS/MenuMeters"
chmod +x "$APP/Contents/MacOS/MenuMeters"

# Info.plist is already a concrete, Xcode-variable-free plist.
cp MenuMeters-Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Application resources.
cp Resources/MenuMeters.icns "$RES/"
cp Resources/v2.0.8alert.rtf "$RES/"
cp Resources/com.ragingmenace.MenuMeters.plist "$RES/"
cp Resources/releases.html "$RES/"
cp LICENSE "$RES/"
cp Resources/DiskIcons/*.tiff "$RES/"
cp -R Resources/*.lproj "$RES/"

# Ad-hoc signing is enough for local use. Release builds should be signed with
# a Developer ID identity instead.
if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - "$APP" >/dev/null
    codesign --verify --deep --strict "$APP"
fi

echo "BUILD OK"
file "$APP/Contents/MacOS/MenuMeters"
echo "Output: $APP"
