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
# Ad hoc signature by default. Every ad hoc build has a new signature, so macOS drops the
# Input Monitoring and Accessibility grants after each rebuild. To keep them across builds,
# create a self-signed "Code Signing" certificate in Keychain Access and pass its name:
#   CODESIGN_ID="Clicktalk Dev" ./build.sh
codesign --force --sign "${CODESIGN_ID:--}" "$APP"

echo "Built $PWD/$APP"

# Quit a running copy, otherwise `open` just brings the old binary forward.
if pgrep -xq Clicktalk; then
  pkill -x Clicktalk
  sleep 1
fi
open "$APP"
echo "Launched. Install permanently with: mv $APP /Applications/"
