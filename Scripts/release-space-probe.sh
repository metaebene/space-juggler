#!/bin/zsh
# Builds the release disk image of Space Probe (ADR-0006), as Space Glider does (its ADR-0016): the universal app
# with Space Juggler.app inside, both signed with Developer ID Application, hardened runtime and a secure timestamp, in
# a disk image with a link to /Applications; the image is signed, notarized and stapled → dist/SpaceProbe-<version>.dmg.
# Usage: Scripts/release-space-probe.sh VERSION [--allow-dirty] [--no-notarize]
#   VERSION: the release tag (x.y.z). --no-notarize stops after signing the image (nothing sent to Apple).
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
VERSION="${1:?usage: Scripts/release-space-probe.sh VERSION [--allow-dirty] [--no-notarize]}"
shift
IDENTITY="${IDENTITY:-Developer ID Application: Tim Francis Pritlove (MZ2D45J5VM)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-stagehand-notary}"
VOLUME="Space Probe"
STAGE="$ROOT/.build/release-probe"
OUTPUT="$ROOT/dist/SpaceProbe-$VERSION.dmg"

ALLOW_DIRTY=0
NOTARIZE=1
for option in "$@"; do
  case "$option" in
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --no-notarize) NOTARIZE=0 ;;
    *) echo "Unknown option $option" >&2; exit 64 ;;
  esac
done

if [[ $ALLOW_DIRTY == 0 && -n "$(git status --porcelain)" ]]; then
  echo "Uncommitted changes; commit first (or --allow-dirty to try the script)." >&2
  exit 1
fi
if ! security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
  echo "No \"$IDENTITY\" in the keychain." >&2
  exit 2
fi

echo "== Tests"
swift test >/dev/null

echo "== Universal app $VERSION"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$ROOT/dist"
APP=$(SIGN_IDENTITY="$IDENTITY" UNIVERSAL=1 TIMESTAMP=1 SHORT_VERSION="$VERSION" \
  Scripts/build-space-probe.sh release "$STAGE" | tail -1)
ln -s /Applications "$STAGE/Applications"

echo "== Disk image"
rm -f "$OUTPUT"
diskutil image create from --format UDZO --volumeName "$VOLUME" "$STAGE" "$OUTPUT" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$OUTPUT"
codesign --verify --strict "$OUTPUT"

if [[ $NOTARIZE == 0 ]]; then
  echo "Signed, not notarized (--no-notarize): $OUTPUT"
  exit 0
fi

echo "== Notarizing"
xcrun notarytool submit "$OUTPUT" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$OUTPUT"
spctl --assess --type open --context context:primary-signature -v "$OUTPUT"
shasum -a 256 "$OUTPUT"
echo "Release: $OUTPUT"
