#!/bin/zsh
# Builds SpaceMouse Probe.app (ADR-0006): the SpaceMouseProbe product as an app bundle with Space Juggler.app inside
# (Contents/Helpers, ADR-0002), both signed.
# Usage: Scripts/build-spacemouse-probe.sh [debug|release] [output directory]
# Environment as for build-space-juggler.sh: SIGN_IDENTITY (default "-", ad hoc), UNIVERSAL=1, TIMESTAMP=1; SHORT_VERSION.
# Prints the path of the bundle as its last line.
set -euo pipefail
cd "${0:A:h}/.."
CONFIG=${1:-debug}
OUT=${2:-.build/spacemouse-probe}
IDENTITY=${SIGN_IDENTITY:--}
ARCHS=()
[[ "${UNIVERSAL:-0}" == 1 ]] && ARCHS=(--arch arm64 --arch x86_64)
swift build -c "$CONFIG" "${ARCHS[@]}" --product SpaceMouseProbe >&2
BIN="$(swift build -c "$CONFIG" "${ARCHS[@]}" --show-bin-path)"
VERSION=$(sed -nE 's/^ *public static let version = ([0-9]+).*/\1/p' Sources/SpaceJugglerProtocol/Wire.swift)
APP="$OUT/SpaceMouse Probe.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$BIN/SpaceMouseProbe" "$APP/Contents/MacOS/SpaceMouseProbe"
# CFBundleShortVersionString: the release (SHORT_VERSION, x.y.z), else Space Juggler's version; CFBundleVersion: the latter.
sed -e "s/__SHORT_VERSION__/${SHORT_VERSION:-$VERSION}/g" -e "s/__VERSION__/$VERSION/g" App/Probe/Info.plist > "$APP/Contents/Info.plist"
# The icon (ADR-0007): Assets.car for macOS 26+ (Liquid Glass), AppIcon.icns for older systems.
xcrun actool App/Probe/AppIcon.icon --compile "$APP/Contents/Resources" --app-icon AppIcon --platform macosx \
  --minimum-deployment-target 14.0 --output-partial-info-plist "$(mktemp -t SpaceMouseProbe-icon).plist" >/dev/null
cp -R App/Probe/de.lproj "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/en.lproj"
JUGGLER=$(Scripts/build-space-juggler.sh "$CONFIG" "$APP/Contents/Helpers" | tail -1)
SIGN_OPTIONS=(--force --options runtime --sign "$IDENTITY")
[[ "${TIMESTAMP:-0}" == 1 ]] && SIGN_OPTIONS+=(--timestamp)
codesign "${SIGN_OPTIONS[@]}" "$APP"
codesign --verify --strict --deep "$APP"
echo "Built SpaceMouse Probe $VERSION ($CONFIG${UNIVERSAL:+, universal}) with $JUGGLER" >&2
echo "$APP"
