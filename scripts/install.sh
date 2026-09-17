#!/usr/bin/env bash
# Build FaceMac and install it to a stable location, then launch it.
#
# The app is signed with a stable "Apple Development" identity (see project.yml),
# so macOS Camera and Accessibility grants survive rebuilds. Keep the app in one
# place — mixing locations can make TCC treat it as different apps.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/.build/DerivedData"
DEST="$HOME/Applications"
APP="$DEST/FaceMac.app"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
  echo "warning: no 'Apple Development' signing identity found."
  echo "         Open Xcode > Settings > Accounts and add your Apple ID,"
  echo "         or change CODE_SIGN_IDENTITY in project.yml."
fi

echo "building..."
(cd "$ROOT" && xcodegen generate >/dev/null)
xcodebuild \
  -project "$ROOT/FaceMac.xcodeproj" \
  -scheme FaceMac \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  build >/dev/null

echo "installing to $APP"
mkdir -p "$DEST"
pkill -f "FaceMac.app/Contents/MacOS/FaceMac" 2>/dev/null || true
sleep 0.5
rm -rf "$APP"
cp -R "$DERIVED/Build/Products/Debug/FaceMac.app" "$APP"

echo "signature:"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier" || true

open "$APP"
echo "launched $APP"
