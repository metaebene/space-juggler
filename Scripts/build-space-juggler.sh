#!/bin/zsh
# Builds Space Juggler.app (ADR-0002): the SpaceJuggler product wrapped into an LSUIElement bundle, signed.
# Usage: Scripts/build-space-juggler.sh [debug|release] [output directory]
# Environment: SIGN_IDENTITY (default "-", ad hoc; clients pass their own identity), UNIVERSAL=1 (arm64 + x86_64), TIMESTAMP=1 (for notarization),
# SCRATCH_PATH (absolute; where SwiftPM builds, default the package's .build; clients pass their own, since SwiftPM's
# checkout of a dependency is read-only).
# Prints the path of the bundle as its last line. Clients embed it as Contents/Helpers/Space Juggler.app.
set -euo pipefail
cd "${0:A:h}/.."
CONFIG=${1:-debug}
OUT=${${2:-.build/space-juggler}:A}
IDENTITY=${SIGN_IDENTITY:--}
ARCHS=()
[[ "${UNIVERSAL:-0}" == 1 ]] && ARCHS=(--arch arm64 --arch x86_64)
SCRATCH=()
[[ -n "${SCRATCH_PATH:-}" ]] && SCRATCH=(--scratch-path "$SCRATCH_PATH")
swift build -c "$CONFIG" "${ARCHS[@]}" "${SCRATCH[@]}" --product SpaceJuggler >&2
BIN="$(swift build -c "$CONFIG" "${ARCHS[@]}" "${SCRATCH[@]}" --show-bin-path)"
VERSION=$(sed -nE 's/^ *public static let version = ([0-9]+).*/\1/p' Sources/SpaceJugglerProtocol/Wire.swift)
APP="$OUT/Space Juggler.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SpaceJuggler" "$APP/Contents/MacOS/SpaceJuggler"
sed "s/__VERSION__/$VERSION/g" App/Info.plist > "$APP/Contents/Info.plist"
# The icon (ADR-0008), so Activity Monitor and Finder show the menu bar symbol: Assets.car for macOS 26+, AppIcon.icns before.
# Absolute paths: actool hands the work to a shared ibtoold, which resolves relative paths in its own directory.
xcrun actool "$PWD/App/AppIcon.icon" --compile "$APP/Contents/Resources" --app-icon AppIcon --platform macosx \
  --minimum-deployment-target 14.0 --output-partial-info-plist "$(mktemp -t SpaceJuggler-icon).plist" >/dev/null
cp -R App/de.lproj "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/en.lproj"
SIGN_OPTIONS=(--force --options runtime --entitlements App/SpaceJuggler.entitlements --sign "$IDENTITY")
[[ "${TIMESTAMP:-0}" == 1 ]] && SIGN_OPTIONS+=(--timestamp)
codesign "${SIGN_OPTIONS[@]}" "$APP"
codesign --verify --strict "$APP"
echo "Built Space Juggler $VERSION ($CONFIG${UNIVERSAL:+, universal})" >&2
echo "$APP"
