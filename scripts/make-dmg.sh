#!/usr/bin/env bash
#
# Builds Vitality in Release and packages it as a .dmg.
#
# The script picks the best signing identity available and tells you plainly
# what the result can and cannot do:
#
#   Developer ID Application  -> runs on any Mac (notarise it too, see below)
#   Apple Development         -> runs on YOUR Mac only; Gatekeeper rejects a
#                                downloaded copy on anyone else's
#
# To produce a build strangers can install by drag-and-drop you need the paid
# Apple Developer Program, a "Developer ID Application" certificate, and
# notarisation. Once you have the certificate, store notary credentials once:
#
#   xcrun notarytool store-credentials vitality-notary \
#       --apple-id you@example.com --team-id XXXXXXXXXX \
#       --password <app-specific-password>
#
# then run:  NOTARIZE=1 ./scripts/make-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Vitality"
BUILD_DIR="$ROOT/build"
STAGE_DIR="$BUILD_DIR/dmg-stage"
NOTARY_PROFILE="${NOTARY_PROFILE:-vitality-notary}"

command -v xcodegen >/dev/null 2>&1 || {
  echo "error: xcodegen not found. Install it with: brew install xcodegen" >&2
  exit 1
}
[ -f "$ROOT/Local.xcconfig" ] || {
  echo "error: Local.xcconfig missing. Copy it and set your Team ID:" >&2
  echo "         cp Local.xcconfig.example Local.xcconfig" >&2
  exit 1
}

# xcodebuild needs a full Xcode, not the Command Line Tools.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app; do
    [ -d "$candidate" ] && { export DEVELOPER_DIR="$candidate/Contents/Developer"; break; }
  done
fi
echo "==> Xcode: ${DEVELOPER_DIR:-<xcode-select default>}"

# Prefer a Developer ID identity when one exists — that's the only kind that
# produces a build other people can actually run.
DEVID="$(security find-identity -v -p codesigning 2>/dev/null \
         | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)"

SIGN_ARGS=()
if [ -n "$DEVID" ]; then
  echo "==> Signing identity: $DEVID (distributable)"
  SIGN_ARGS=(
    CODE_SIGN_IDENTITY="Developer ID Application"
    CODE_SIGN_STYLE=Manual
    ENABLE_HARDENED_RUNTIME=YES
  )
else
  echo "==> Signing identity: Apple Development (personal use only)"
fi

echo "==> Generating project"
xcodegen generate

echo "==> Building Release"
rm -rf "$BUILD_DIR"
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -allowProvisioningUpdates \
  ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} \
  build

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "error: build produced no app at $APP_PATH" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

echo "==> Staging disk image"
rm -rf "$STAGE_DIR"; mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"   # enables drag-to-install

echo "==> Creating $(basename "$DMG_PATH")"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" \
  -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$STAGE_DIR"

if [ -n "$DEVID" ] && [ "${NOTARIZE:-0}" = "1" ]; then
  echo "==> Notarising (this uploads the DMG to Apple and can take a few minutes)"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "==> Stapling ticket"
  xcrun stapler staple "$DMG_PATH"
fi

echo
echo "Built $DMG_PATH"
echo
# Report what the artefact can actually do rather than leaving it to be found out.
if spctl -a -t exec "$APP_PATH" >/dev/null 2>&1; then
  echo "Gatekeeper: ACCEPTED — this build runs on any Mac."
else
  cat <<'EOF'
Gatekeeper: REJECTED for downloaded copies.

This build runs on THIS Mac (locally built files aren't quarantined, so
Gatekeeper never checks them). If someone downloads it, their browser stamps
com.apple.quarantine on the file, Gatekeeper evaluates it, and macOS refuses
to open it.

To distribute it you need:
  1. The paid Apple Developer Program (~$99/yr)
  2. A "Developer ID Application" certificate
  3. Notarisation — then re-run with: NOTARIZE=1 ./scripts/make-dmg.sh

This script picks up a Developer ID certificate automatically once one exists.
EOF
fi
