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
# Signing identity: CODESIGN_ID if set, else the "Clicktalk Dev" certificate from
# ./make-cert.sh if present, else ad hoc. Ad hoc signatures change on every build, and
# macOS drops the Input Monitoring and Accessibility grants when the signature changes.
ID="${CODESIGN_ID:-}"
if [ -z "$ID" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q '"Clicktalk Dev"'; then
  ID="Clicktalk Dev"
fi
if [ -n "$ID" ]; then
  codesign --force --sign "$ID" "$APP"
  echo "Signed with \"$ID\"; permissions survive rebuilds."
else
  codesign --force --sign - "$APP"
  echo "Signed ad hoc. Permissions reset on every rebuild; run ./make-cert.sh once to fix that."
fi

echo "Built $PWD/$APP"

# Quit a running copy, otherwise `open` just brings the old binary forward.
if pgrep -xq Clicktalk; then
  pkill -x Clicktalk
  sleep 1
fi
open "$APP"
echo "Launched. Install permanently with: mv $APP /Applications/"
