#!/bin/sh
# Archives Kinwall (iPhone/iPad app with its widgets and Watch app) and uploads it to App Store
# Connect for TestFlight. Signing is automatic through the Apple account signed in to Xcode
# (Xcode → Settings → Accounts); it creates the certificates, App IDs and profiles it needs.
#   TEAM=ABCDE12345 scripts/testflight.sh            # archive + upload
#   TEAM=ABCDE12345 UPLOAD=0 scripts/testflight.sh   # archive + export an .ipa only
set -eu
: "${TEAM:?Set TEAM to your Apple Developer team ID (developer.apple.com → Membership)}"
cd "$(dirname "$0")/.."
OUT="${OUT:-/tmp/kinwall-testflight}"   # outside ~/Documents: codesign trips over Finder metadata there
BUILD="${BUILD:-$(date +%Y%m%d%H%M)}"   # every upload needs a new build number
rm -rf "$OUT" && mkdir -p "$OUT"
xcodegen generate --quiet
xcodebuild archive -project Kinwall.xcodeproj -scheme Kinwall -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/Kinwall.xcarchive" -derivedDataPath "$OUT/dd" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CURRENT_PROJECT_VERSION="$BUILD" | tail -3
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$([ "${UPLOAD:-1}" = 1 ] && echo upload || echo export)</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/Kinwall.xcarchive" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" -allowProvisioningUpdates | tail -3
echo "Build $BUILD: $([ "${UPLOAD:-1}" = 1 ] && echo 'uploaded; it shows in TestFlight once processed (about 10-30 minutes)' || echo "$OUT/export")"
