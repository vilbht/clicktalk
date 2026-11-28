#!/bin/bash
# Builds EucLink.app, installs it in /Applications and opens it.
# Needs macOS 13 or later and the Xcode command line tools (xcode-select --install).
#
#   ./build.sh          build, install in /Applications, open
#   ./build.sh local    build and open from this folder, without installing
#   ./build.sh docs     build, then render the README images into docs/images
#   ./build.sh ci       build signed ad hoc and run the tests; installs nothing (used by CI)
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-install}"

APP="EucLink.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling with $(swiftc --version 2>&1 | head -1)…"
swiftc -O -parse-as-library \
  -target "$(uname -m)-apple-macos13.0" \
  -framework AppKit -framework SwiftUI -framework IOBluetooth -framework IOKit \
  -framework CoreBluetooth -framework ServiceManagement -framework CryptoKit -framework Security \
  Sources/*.swift -o "$APP/Contents/MacOS/EucLink"

cp Info.plist "$APP/Contents/Info.plist"

# The icon is drawn by the app itself, so the repository holds no image assets.
ICONSET="$(mktemp -d)/AppIcon.iconset"
"$APP/Contents/MacOS/EucLink" --render-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

# Signing identity: CODESIGN_ID if set, else the "EucLink Dev" certificate from
# ./make-cert.sh if present, else ad hoc. Ad hoc signatures change on every build, and
# macOS drops the Input Monitoring and Accessibility grants when the signature changes.
ID="${CODESIGN_ID:-}"
if [ "$MODE" = "ci" ]; then
  ID=""
elif [ -z "$ID" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q '"EucLink Dev"'; then
  ID="EucLink Dev"
fi
# --options runtime turns on the hardened runtime, which stops other programs from
# injecting code into EucLink to borrow its Input Monitoring and Accessibility grants.
if [ -n "$ID" ]; then
  echo "macOS asks to use the \"$ID\" key: click Allow, never Always Allow."
  codesign --force --options runtime --sign "$ID" "$APP"
  echo "Signed with \"$ID\"; permissions survive rebuilds."
else
  codesign --force --options runtime --sign - "$APP"
  echo "Signed ad hoc. Permissions reset on every rebuild; run ./make-cert.sh once to avoid that."
fi

if [ "$MODE" = "ci" ]; then
  # Privacy: only the optional update check may go online, and only to this project on
  # GitHub. Networking code in any other file, or another address in that file, fails here.
  echo "Checking that only the update check can go online…"
  if grep -nE 'URLSession|URLRequest|NWConnection|NSURLConnection|CFNetwork|CFSocket|CFStream|WKWebView|import Network' \
       Sources/*.swift | grep -v '^Sources/Updates.swift:'; then
    echo "Networking code outside Sources/Updates.swift. See PRIVACY.md."
    exit 1
  fi
  if grep -oE 'https?://[^"]+' Sources/Updates.swift \
       | grep -vE '^https://(api\.github\.com/repos|github\.com)/vilbht/euclink/'; then
    echo "Sources/Updates.swift names an address other than this project on GitHub."
    exit 1
  fi

  echo "Compiling tests…"
  TESTS="$(mktemp -d)"
  swiftc -target "$(uname -m)-apple-macos13.0" -framework AppKit \
    Sources/Keys.swift Sources/Leftovers.swift Sources/Version.swift Sources/Gestures.swift Sources/Model.swift Tests/main.swift -o "$TESTS/tests"
  "$TESTS/tests"
  rm -rf "$TESTS"

  # Start the app once and check it is still running after five seconds. This catches a
  # crash at launch that compiling and the unit tests cannot see.
  echo "Launching once to check it starts…"
  "$APP/Contents/MacOS/EucLink" &
  PID=$!
  sleep 5
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    echo "EucLink starts and stays up."
  else
    STATUS=0
    wait "$PID" || STATUS=$?
    echo "EucLink exited at launch with status ${STATUS}."
    exit 1
  fi
  exit 0
fi

if [ "$MODE" = "docs" ]; then
  "$APP/Contents/MacOS/EucLink" --render-docs docs/images
  echo "README images are in docs/images."
  exit 0
fi

# Quit a running copy, otherwise `open` just brings the old one forward.
if pgrep -xq EucLink; then
  pkill -x EucLink || true
  sleep 1
fi

if [ "$MODE" = "local" ]; then
  open "$APP"
  echo "Opened $PWD/$APP"
  exit 0
fi

DEST="/Applications/EucLink.app"
if rm -rf "$DEST" 2>/dev/null && ditto "$APP" "$DEST"; then
  open "$DEST"
  echo "Installed and opened $DEST"
else
  open "$APP"
  echo "Could not write to /Applications. Opened $PWD/$APP instead; the app offers to copy itself."
fi
