#!/bin/bash
# Builds build/Utter.app from the Swift package and signs it.
#
#   scripts/build-app.sh            # release build
#   scripts/build-app.sh debug      # debug build
#   SIGN_IDENTITY="My Cert" scripts/build-app.sh
#
# macOS ties the Accessibility permission to the app's signature. Ad-hoc
# signatures change on every build, so you'd have to re-grant it each time.
# Signing with a stable identity (any code-signing certificate in your
# keychain, even a self-signed one) avoids that. Without SIGN_IDENTITY the
# first valid identity is used, falling back to ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Utter.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
/bin/cp -f "$BIN_DIR/Utter" "$APP/Contents/MacOS/Utter"
/bin/cp -f Resources/Info.plist "$APP/Contents/Info.plist"
/bin/cp -f Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  # Use the SHA-1 hash: names can be ambiguous when a certificate is duplicated.
  IDENTITY="$(security find-identity -v -p codesigning | awk '/"/ { print $2; exit }')"
fi
IDENTITY="${IDENTITY:--}"

codesign --force --options runtime --entitlements Resources/Utter.entitlements --sign "$IDENTITY" "$APP"
echo "Built $APP (signed with: $IDENTITY)"
