#!/bin/bash
# Removes EucLink from this Mac: the app, its settings, its permission entries and
# its login item. Leaves this source folder alone. It also removes Clicktalk, the
# app's earlier name, so an old copy cannot hold the button alongside EucLink.
#
#   ./uninstall.sh        remove the app and everything it stored
#   ./uninstall.sh --all  also delete the "EucLink Dev" and "Clicktalk Dev" signing certificates
set -u
cd "$(dirname "$0")"

remove() {
  local name="$1" id="$2"
  local apps=("/Applications/$name.app" "$HOME/Applications/$name.app" "./$name.app")
  local found=""
  for app in "${apps[@]}"; do [ -e "$app" ] && found=1; done
  if [ -z "$found" ] && ! defaults read "$id" >/dev/null 2>&1 && [ "$name" != EucLink ]; then
    return
  fi

  echo "Quitting ${name}…"
  pkill -x "$name" 2>/dev/null && sleep 1

  for app in "${apps[@]}"; do
    if [ -x "$app/Contents/MacOS/$name" ]; then
      "$app/Contents/MacOS/$name" --unregister-login 2>/dev/null
    fi
  done

  echo "Removing ${name}…"
  rm -rf "${apps[@]}"
  defaults delete "$id" 2>/dev/null
  rm -f "$HOME/Library/Preferences/$id.plist"
  rm -rf "$HOME/Library/Saved Application State/$id.savedState" \
    "$HOME/Library/Caches/$id" "$HOME/Library/HTTPStorages/$id"
  security delete-generic-password -s "$id.settings-seal" >/dev/null 2>&1
  for service in ListenEvent Accessibility BluetoothAlways; do
    tccutil reset "$service" "$id" >/dev/null 2>&1
  done
}

remove_cert() {
  local cert_name="$1"
  local cert
  cert="$(mktemp)"
  if security find-certificate -c "$cert_name" -p >"$cert" 2>/dev/null; then
    echo "Removing the code-signing trust and certificate for ${cert_name}…"
    security remove-trusted-cert "$cert" >/dev/null 2>&1 \
      || echo "No trust setting found, or removal was cancelled."
    security delete-identity -c "$cert_name" >/dev/null 2>&1
  fi
  rm -f "$cert"
}

remove EucLink local.euclink
remove Clicktalk local.clicktalk

if [ "${1:-}" = "--all" ]; then
  remove_cert "EucLink Dev"
  remove_cert "Clicktalk Dev"
fi

echo "EucLink is uninstalled."
echo "If EucLink or Clicktalk still shows in System Settings > General > Login Items, remove it there."
