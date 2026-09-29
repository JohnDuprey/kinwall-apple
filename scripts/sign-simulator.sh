#!/bin/bash
# Re-signs a simulator build with your Apple Development identity so Siri, Shortcuts and the Controls
# work in the Simulator: a simulator build is signed ad hoc (no team), and iOS's App Intents service
# turns away an app without a team ("Couldn't find AppShortcutsProvider", entities "not registered").
# Each bundle keeps its entitlements. Simulator builds only; devices are signed by Xcode as usual.
#   IDENTITY=<SHA-1 or name from `security find-identity -v -p codesigning`> scripts/sign-simulator.sh path/to/Kinwall.app
set -euo pipefail
: "${IDENTITY:?Set IDENTITY to your Apple Development signing identity}"
APP="${1:?Pass the built Kinwall.app}"
find "$APP" -depth \( -name "*.appex" -o -name "*.app" \) -print0 | while IFS= read -r -d '' b; do
  codesign --force --sign "$IDENTITY" --preserve-metadata=entitlements,identifier "$b"
done
codesign -dv "$APP" 2>&1 | grep TeamIdentifier
