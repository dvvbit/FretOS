#!/bin/bash
# Builds dist/FretOS.app (universal, ad-hoc signed) and dist/FretOS-<version>.zip.
set -euo pipefail
VERSION="${1:-1.0.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/FretOS"
DIST="$ROOT/dist"
APP="$DIST/FretOS.app"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"

[ -f "$PKG/Vendor/libusb/lib/libusb-1.0.0.dylib" ] || "$ROOT/scripts/build-libusb.sh"

echo "→ building release (arm64 + x86_64)"
swift build --package-path "$PKG" -c release --arch arm64 --arch x86_64 > "$DIST.build.log" 2>&1 || { tail -30 "$DIST.build.log"; exit 1; }
BIN="$(swift build --package-path "$PKG" -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "→ assembling app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/FretOS" "$APP/Contents/MacOS/FretOS"
cp "$PKG/Vendor/libusb/lib/libusb-1.0.0.dylib" "$APP/Contents/Frameworks/"
cp "$PKG/Sources/FretOS/Resources/PressStart2P-Regular.ttf" "$APP/Contents/Resources/"
cp "$PKG/Sources/FretOS/Resources/Logo.png" "$APP/Contents/Resources/"
cp "$PKG/Packaging/AppIcon.icns" "$APP/Contents/Resources/"
sed "s/__VERSION__/$VERSION/g" "$PKG/Packaging/Info.plist" > "$APP/Contents/Info.plist"
# drop the dev-only rpath into the build folder; keep @executable_path/../Frameworks
install_name_tool -delete_rpath "$PKG/Vendor/libusb/lib" "$APP/Contents/MacOS/FretOS" 2>/dev/null || true
mkdir -p "$APP/Contents/Resources/Licenses"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_LICENSES.md" "$APP/Contents/Resources/Licenses/"
cp "$PKG/Vendor/libusb/COPYING" "$APP/Contents/Resources/Licenses/libusb-COPYING.txt"
cp "$PKG/Sources/FretOS/Resources/OFL.txt" "$APP/Contents/Resources/Licenses/PressStart2P-OFL.txt"

echo "→ stripping build paths and debug info"
strip -S -x "$APP/Contents/MacOS/FretOS"
strip -S -x "$APP/Contents/Frameworks/libusb-1.0.0.dylib"
# Refuse to ship anything that still contains a home-folder path.
if LC_ALL=C grep -rlaE "/Users/[^/]+/" "$APP" >/dev/null; then
  echo "✗ build path found in app:"; LC_ALL=C grep -rlaE "/Users/[^/]+/" "$APP"; exit 1
fi

echo "→ signing (ad-hoc)"
codesign --force -s - "$APP/Contents/Frameworks/libusb-1.0.0.dylib"
codesign --force -s - --identifier io.github.fretos.FretOS "$APP"

echo "→ zipping"
ZIP="$DIST/FretOS-$VERSION.zip"
rm -f "$ZIP"
STAGE="$DIST/stage/FretOS $VERSION"
rm -rf "$DIST/stage"; mkdir -p "$STAGE"
ditto --norsrc --noextattr --noqtn --noacl "$APP" "$STAGE/FretOS.app"
cp "$PKG/Packaging/READ-ME-FIRST.txt" "$STAGE/READ ME FIRST.txt"
( cd "$DIST/stage" && ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "FretOS $VERSION" "$ZIP" )
rm -rf "$DIST/stage"
cp "$ROOT/README.md" "$DIST/README.md"
echo "✓ $APP"
echo "✓ $ZIP ($(du -h "$ZIP" | cut -f1))"
