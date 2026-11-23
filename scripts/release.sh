#!/bin/bash
# Build, sign, notarize and staple a Coreader DMG for direct download.
#
#   scripts/release.sh                 sign with the Developer ID identity in the keychain
#   SIGN_IDENTITY=- scripts/release.sh ad-hoc dry run: same signing flags, no notarization
#
# Needs a "Developer ID Application" identity (see docs/releasing.md) and `asc` signed in
# with a key that may notarize. On the Mac mini run it as `ios-build scripts/release.sh`
# so the signing keychain is unlocked.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
  [[ -n "$IDENTITY" ]] || { echo "No Developer ID Application identity found. See docs/releasing.md." >&2; exit 1; }
fi

VERSION=$(awk '/MARKETING_VERSION:/ {print $2; exit}' project.yml)
LABEL="${AGENT_NAME:-RELEASE}"
APP="build/DerivedData/$LABEL/Build/Products/Release/Coreader.app"
DMG="dist/Coreader-$VERSION.dmg"

xcodegen generate --spec project.yml >/dev/null
AGENT_NAME="$LABEL" make build CONFIGURATION=Release

# Inside out: the embedded command first, then the app. Hardened runtime and a secure
# timestamp are what notarization requires; ad-hoc signing cannot be timestamped.
STAMP=(--timestamp); [[ "$IDENTITY" == "-" ]] && STAMP=(--timestamp=none)
sign() { codesign --force --options runtime "${STAMP[@]}" --sign "$IDENTITY" "$@"; }
sign --identifier com.sushil.coreader.cli "$APP/Contents/Helpers/coreader"
sign --entitlements Sources/CoreaderApp/Coreader.entitlements "$APP"
codesign --verify --deep --strict "$APP"

mkdir -p dist; rm -f "$DMG"
scripts/build_dmg.sh --app-path "$APP" --output "$DMG" --volume-name Coreader

if [[ "$IDENTITY" == "-" ]]; then
  echo "Dry run (ad-hoc): $DMG is not notarized and will be blocked on other Macs."
  exit 0
fi

sign "$DMG"
asc notarization submit --file "$DMG" --wait
asc notarization staple --file "$DMG" --confirm
spctl --assess --type open --context context:primary-signature -v "$DMG"
echo "Released: $DMG"
