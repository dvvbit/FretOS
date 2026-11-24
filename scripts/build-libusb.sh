#!/bin/bash
# Builds libusb as a universal (arm64 + x86_64) dylib into FretOS/Vendor/libusb.
# libusb is LGPL-2.1; FretOS links it dynamically and ships its license (COPYING).
set -euo pipefail

VERSION=1.0.27
SHA256=ffaa41d741a8a3bee244ac8e54a72ea05bf2879663c098c82fc5757853441575
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/FretOS/Vendor/libusb"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "→ downloading libusb $VERSION"
curl -sSL -o "$WORK/libusb.tar.bz2" \
  "https://github.com/libusb/libusb/releases/download/v$VERSION/libusb-$VERSION.tar.bz2"
echo "$SHA256  $WORK/libusb.tar.bz2" | shasum -a 256 -c -

tar -xjf "$WORK/libusb.tar.bz2" -C "$WORK"
cd "$WORK/libusb-$VERSION"

echo "→ building universal"
# Use Xcode's toolchain + SDK explicitly (a stale Command Line Tools install can break plain `cc`).
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
export CC="$(xcrun -f clang)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
./configure --prefix="$WORK/install" --disable-static --disable-dependency-tracking \
  CFLAGS="-isysroot $SDK -arch arm64 -arch x86_64 -mmacosx-version-min=13.0 -O2" \
  LDFLAGS="-isysroot $SDK -arch arm64 -arch x86_64 -mmacosx-version-min=13.0" > "$WORK/configure.log"
make -j"$(sysctl -n hw.ncpu)" > "$WORK/make.log"
make install > /dev/null

rm -rf "$OUT"; mkdir -p "$OUT/include" "$OUT/lib"
cp "$WORK/install/include/libusb-1.0/libusb.h" "$OUT/include/"
cp "$WORK/install/lib/libusb-1.0.0.dylib" "$OUT/lib/"
ln -sf libusb-1.0.0.dylib "$OUT/lib/libusb-1.0.dylib"
install_name_tool -id @rpath/libusb-1.0.0.dylib "$OUT/lib/libusb-1.0.0.dylib"
cp COPYING "$OUT/COPYING"

lipo -info "$OUT/lib/libusb-1.0.0.dylib"
echo "✓ libusb $VERSION → $OUT"
