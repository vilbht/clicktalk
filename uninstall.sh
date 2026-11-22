#!/bin/bash
# Removes Clicktalk from this Mac: the app, its settings, its permission entries and
# its login item. Leaves this source folder alone.
#
#   ./uninstall.sh        remove the app and everything it stored
#   ./uninstall.sh --all  also delete the "Clicktalk Dev" signing certificate
set -u
cd "$(dirname "$0")"

echo "Quitting Clicktalk…"
pkill -x Clicktalk 2>/dev/null && sleep 1

for app in /Applications/Clicktalk.app "$HOME/Applications/Clicktalk.app" ./Clicktalk.app; do
  if [ -x "$app/Contents/MacOS/Clicktalk" ]; then
    "$app/Contents/MacOS/Clicktalk" --unregister-login 2>/dev/null
  fi
done

echo "Removing the app…"
rm -rf /Applications/Clicktalk.app "$HOME/Applications/Clicktalk.app" ./Clicktalk.app

echo "Removing settings…"
defaults delete local.clicktalk 2>/dev/null
rm -f "$HOME/Library/Preferences/local.clicktalk.plist"

echo "Resetting permissions…"
for service in ListenEvent Accessibility BluetoothAlways; do
  tccutil reset "$service" local.clicktalk >/dev/null 2>&1
done

if [ "${1:-}" = "--all" ]; then
  echo "Deleting the Clicktalk Dev signing certificate…"
  security delete-identity -c "Clicktalk Dev" >/dev/null 2>&1 \
    || echo "No Clicktalk Dev certificate found."
fi

echo "Clicktalk is uninstalled."
echo "If Clicktalk still shows in System Settings > General > Login Items, remove it there."
