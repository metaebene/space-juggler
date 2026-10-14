#!/bin/zsh
# Builds Space Juggler.app (ADR-0002): the SpaceJuggler product wrapped into an LSUIElement bundle, signed.
# Usage: Scripts/build-space-juggler.sh [debug|release] [output directory]
# Environment: SIGN_IDENTITY (default "-", ad hoc; clients pass their own identity), UNIVERSAL=1 (arm64 + x86_64), TIMESTAMP=1 (for notarization).
# Prints the path of the bundle as its last line. Clients embed it as Contents/Helpers/Space Juggler.app.
set -euo pipefail
cd "${0:A:h}/.."
CONFIG=${1:-debug}
OUT=${2:-.build/space-juggler}
IDENTITY=${SIGN_IDENTITY:--}
ARCHS=()
[[ "${UNIVERSAL:-0}" == 1 ]] && ARCHS=(--arch arm64 --arch x86_64)
swift build -c "$CONFIG" "${ARCHS[@]}" --product SpaceJuggler >&2
BIN="$(swift build -c "$CONFIG" "${ARCHS[@]}" --show-bin-path)"
VERSION=$(sed -nE 's/^ *public static let version = ([0-9]+).*/\1/p' Sources/SpaceJugglerProtocol/Wire.swift)
APP="$OUT/Space Juggler.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SpaceJuggler" "$APP/Contents/MacOS/SpaceJuggler"
sed "s/__VERSION__/$VERSION/g" App/Info.plist > "$APP/Contents/Info.plist"
cp -R App/de.lproj "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/en.lproj"
SIGN_OPTIONS=(--force --options runtime --entitlements App/SpaceJuggler.entitlements --sign "$IDENTITY")
[[ "${TIMESTAMP:-0}" == 1 ]] && SIGN_OPTIONS+=(--timestamp)
codesign "${SIGN_OPTIONS[@]}" "$APP"
codesign --verify --strict "$APP"
echo "Built Space Juggler $VERSION ($CONFIG${UNIVERSAL:+, universal})" >&2
echo "$APP"
