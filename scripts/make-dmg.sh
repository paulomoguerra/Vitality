#!/usr/bin/env bash
#
# Builds Vitality in Release and packages it as a distributable .dmg.
#
# Signing note: this signs with whatever identity your Local.xcconfig team
# provides. An "Apple Development" identity is enough to run the app on *your*
# own Mac, but macOS will refuse it on anyone else's. Shipping to other people
# needs a "Developer ID Application" certificate (paid Apple Developer Program)
# plus notarisation — see README.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Vitality"
BUILD_DIR="$ROOT/build"
STAGE_DIR="$BUILD_DIR/dmg-stage"

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
    if [ -d "$candidate" ]; then
      export DEVELOPER_DIR="$candidate/Contents/Developer"
      break
    fi
  done
fi
echo "==> Using Xcode at ${DEVELOPER_DIR:-<xcode-select default>}"

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
  build

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "error: build produced no app at $APP_PATH" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

echo "==> Staging disk image contents"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
# The /Applications symlink is what lets the user drag-to-install.
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Creating $DMG_PATH"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGE_DIR"

echo
echo "Built $DMG_PATH"
echo
echo "Signing identity:"
codesign -dv "$APP_PATH" 2>&1 | grep -E "^Authority|^Signature" || true
echo
if ! codesign -dv "$APP_PATH" 2>&1 | grep -q "Developer ID"; then
  cat <<'EOF'
Note: this build is NOT signed with a Developer ID certificate, so it will only
run on Macs provisioned by your development team. To distribute it to others you
need the paid Apple Developer Program, a "Developer ID Application" certificate,
and notarisation via `xcrun notarytool`.
EOF
fi
