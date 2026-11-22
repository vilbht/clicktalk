#!/bin/bash
# Builds Clicky.app next to this script. Needs Xcode command line tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

APP="Clicky.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O \
  -framework AppKit -framework IOBluetooth -framework IOKit -framework ServiceManagement \
  Sources/main.swift -o "$APP/Contents/MacOS/Clicky"

cp Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signature so macOS remembers the Bluetooth permission between launches.
codesign --force --sign - "$APP"

echo "Built $PWD/$APP"
echo "Run:      open $APP"
echo "Install:  mv $APP /Applications/"
