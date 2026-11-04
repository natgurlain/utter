#!/bin/bash
# Builds Utter, installs it to ~/Applications/Utter.app and launches it.
#
# Always run Utter from this installed copy, not from build/: macOS privacy
# permissions (Accessibility, Microphone) and the login item are tied to the
# app's location and signature, and a stable copy keeps them working across
# rebuilds.
#
#   scripts/install.sh
#   INSTALL_DIR=/Applications scripts/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
INSTALLED_APP="$INSTALL_DIR/Utter.app"

scripts/build-app.sh release

# Quit the running copy (only Utter itself).
osascript -e 'quit app id "com.natgurlain.utter"' >/dev/null 2>&1 || true
pkill -x Utter >/dev/null 2>&1 || true
sleep 0.5

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP"
/usr/bin/ditto build/Utter.app "$INSTALLED_APP"
/usr/bin/open "$INSTALLED_APP"
echo "Installed and launched $INSTALLED_APP"
