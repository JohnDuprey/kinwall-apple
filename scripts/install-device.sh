#!/bin/sh
# Builds Kinwall for a paired iPhone or iPad (cable or Wi-Fi) and installs it (a development build: signed through
# the Apple account in Xcode → Settings → Accounts, which also registers the device; the profile
# lasts a year on a paid team). The Watch app is embedded; the iPhone's Watch app installs it.
#   TEAM=ABCDE12345 scripts/install-device.sh            # the only connected device
#   TEAM=ABCDE12345 DEVICE=<udid> scripts/install-device.sh
set -eu
: "${TEAM:?Set TEAM to your Apple Developer team ID (developer.apple.com → Membership)}"
cd "$(dirname "$0")/.."
OUT="${OUT:-/tmp/kinwall-device}"   # outside ~/Documents: codesign trips over Finder metadata there
if [ -z "${DEVICE:-}" ]; then
  DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '(/connected/ || /available/) && !/simulated/ && !/unavailable/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-/) print $i }' | head -1)
  [ -n "$DEVICE" ] || { echo "No paired iPhone or iPad (pair it in Xcode → Window → Devices and Simulators, by cable or over Wi-Fi, and turn on Developer Mode)" >&2; exit 1; }
fi
xcodegen generate --quiet
xcodebuild build -project Kinwall.xcodeproj -scheme Kinwall -configuration Debug \
  -destination "id=$DEVICE" -derivedDataPath "$OUT" -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" | tail -3
xcrun devicectl device install app --device "$DEVICE" "$OUT/Build/Products/Debug-iphoneos/Kinwall.app"
xcrun devicectl device process launch --device "$DEVICE" family.kinwall.app || true
