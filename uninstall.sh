#!/bin/bash
# Removes EucLink from this Mac: the app, its settings, its seal key, its permission
# entries and its login item. Leaves this source folder alone. The app can do the same
# from General > Uninstall.
#
#   ./uninstall.sh        remove the app and everything it stored
#   ./uninstall.sh --all  also delete the "EucLink Dev" signing certificate
set -u
cd "$(dirname "$0")"

NAME="EucLink"
ID="local.euclink"
APPS=("/Applications/$NAME.app" "$HOME/Applications/$NAME.app" "./$NAME.app")

echo "Quitting ${NAME}…"
pkill -x "$NAME" 2>/dev/null && sleep 1

for app in "${APPS[@]}"; do
  if [ -x "$app/Contents/MacOS/$NAME" ]; then
    "$app/Contents/MacOS/$NAME" --unregister-login 2>/dev/null
  fi
done

echo "Removing the app, its settings and its seal key…"
rm -rf "${APPS[@]}"
defaults delete "$ID" 2>/dev/null
rm -f "$HOME/Library/Preferences/$ID.plist"
rm -rf "$HOME/Library/Saved Application State/$ID.savedState" \
  "$HOME/Library/Caches/$ID" "$HOME/Library/HTTPStorages/$ID"
security delete-generic-password -s "$ID.settings-seal" >/dev/null 2>&1

echo "Resetting permissions…"
for service in ListenEvent Accessibility BluetoothAlways; do
  tccutil reset "$service" "$ID" >/dev/null 2>&1
done

if [ "${1:-}" = "--all" ]; then
  CERT="$(mktemp)"
  if security find-certificate -c "EucLink Dev" -p >"$CERT" 2>/dev/null; then
    echo "Removing the code-signing trust and certificate for EucLink Dev…"
    security remove-trusted-cert "$CERT" >/dev/null 2>&1 \
      || echo "No trust setting found, or removal was cancelled."
    security delete-identity -c "EucLink Dev" >/dev/null 2>&1
  fi
  rm -f "$CERT"
fi

echo "EucLink is uninstalled."
echo "If EucLink still shows in System Settings > General > Login Items, remove it there."
