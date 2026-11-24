#!/bin/bash
# Turns a logo PNG into FretOS's app icon.
#   scripts/update-logo.sh "path/to/logo.png"
# Removes any baked-in checkerboard/light background, trims it, adds the neon glow,
# and writes FretOS/Packaging/{logo/logo-clean.png, AppIcon.icns, icon-preview.png}.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$1"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
mkdir -p "$ROOT/FretOS/Packaging/logo"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

swift "$ROOT/scripts/clean-logo.swift" "$SRC" "$ROOT/FretOS/Packaging/logo/logo-clean.png"
swift "$ROOT/scripts/make-icon.swift" "$ROOT/FretOS/Packaging/logo/logo-clean.png" "$WORK/icon1024.png"
mkdir -p "$WORK/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon1024.png" --out "$WORK/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2)); sips -z $d $d "$WORK/icon1024.png" --out "$WORK/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/AppIcon.iconset" -o "$ROOT/FretOS/Packaging/AppIcon.icns"
sips -z 512 512 "$WORK/icon1024.png" --out "$ROOT/FretOS/Packaging/icon-preview.png" >/dev/null
echo "✓ icon updated — run scripts/make-app.sh <version> to rebuild the app"
