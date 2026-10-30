#!/usr/bin/env bash
# Builds build/Cooldown.app and build/Cooldown-<version>.zip
#
#   ./scripts/build-app.sh                      # native architecture
#   ARCHS="arm64 x86_64" ./scripts/build-app.sh # universal (needs full Xcode)
#   VERSION=1.2.0 ./scripts/build-app.sh        # override version
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0-dev}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
ARCHS="${ARCHS:-}"

swift_flags=(-c release)
for arch in $ARCHS; do
  swift_flags+=(--arch "$arch")
done

echo "==> Building Cooldown $VERSION (${ARCHS:-native})"
swift build "${swift_flags[@]}"
BIN_DIR="$(swift build "${swift_flags[@]}" --show-bin-path)"

APP="build/Cooldown.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Cooldown" "$APP/Contents/MacOS/Cooldown"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
  Resources/Info.plist > "$APP/Contents/Info.plist"

if [[ -f Resources/AppIcon.png ]]; then
  echo "==> Generating app icon"
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc signature: required to run on Apple Silicon and for Launch at login.
echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"

echo "==> Zipping"
(cd build && rm -f "Cooldown-$VERSION.zip" && ditto -c -k --keepParent Cooldown.app "Cooldown-$VERSION.zip")

echo "Done: $APP and build/Cooldown-$VERSION.zip"
