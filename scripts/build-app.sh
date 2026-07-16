#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT_DIR="$ROOT/outputs"
APP="$OUTPUT_DIR/Daylight.app"

cd "$ROOT"
swift build -c release --product Daylight
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Daylight" "$APP/Contents/MacOS/Daylight"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
SPARKLE_FRAMEWORK="$(find "$ROOT/.build/artifacts" -path '*/Sparkle.framework' -type d | head -n 1)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
    echo "Sparkle.framework was not found in SwiftPM artifacts" >&2
    exit 1
fi
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

ICON_WORK="$ROOT/work/AppIcon.iconset"
mkdir -p "$ROOT/work"
rm -rf "$ICON_WORK"
mkdir -p "$ICON_WORK"
swift "$ROOT/scripts/make-icon.swift" "$ROOT/work/AppIcon-1024.png"
for spec in "16 16" "16 32" "32 32" "32 64" "128 128" "128 256" "256 256" "256 512" "512 512" "512 1024"; do
    set -- ${(z)spec}
    logical="$1"
    pixels="$2"
    if [[ "$logical" == "$pixels" ]]; then
        name="icon_${logical}x${logical}.png"
    else
        name="icon_${logical}x${logical}@2x.png"
    fi
    sips -z "$pixels" "$pixels" "$ROOT/work/AppIcon-1024.png" --out "$ICON_WORK/$name" >/dev/null
done
iconutil -c icns "$ICON_WORK" -o "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"

codesign --force --deep --sign - \
    --entitlements "$ROOT/Resources/Daylight.entitlements" \
    "$APP"

echo "$APP"
