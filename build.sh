#!/bin/bash
# Builds Clicktalk.app next to this script. Needs Xcode command line tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

APP="Clicktalk.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O \
  -framework AppKit -framework IOBluetooth -framework IOKit -framework ServiceManagement \
  Sources/main.swift -o "$APP/Contents/MacOS/Clicktalk"

cp Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signature so macOS remembers the Bluetooth permission between launches.
codesign --force --sign - "$APP"

echo "Built $PWD/$APP"

# Quit a running copy, otherwise `open` just brings the old binary forward.
if pgrep -xq Clicktalk; then
  pkill -x Clicktalk
  sleep 1
fi
open "$APP"
echo "Launched. Install permanently with: mv $APP /Applications/"
