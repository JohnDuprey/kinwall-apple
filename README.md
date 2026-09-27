# Kinwall for Apple platforms

iPhone, iPad and Apple Watch apps for [Kinwall](https://github.com/JohnDuprey/kinwall), the family wall calendar. Not on the App Store yet: build it yourself and install it on your own devices (see below), or wait for TestFlight. [docs/PLAN.md](docs/PLAN.md) has the plan, the milestones and what a free Apple ID can and can't do.

## Layout

| Path | What |
|---|---|
| `KinwallKit/` | Swift package shared by every target: API client, models, pairing, Keychain storage. No UI. |
| `App/iOS` | The iPhone and iPad app (SwiftUI) |
| `App/Widgets` | WidgetKit extension (Home Screen, Lock Screen, StandBy) |
| `App/Watch` | The Apple Watch app |
| `project.yml` | XcodeGen spec; `xcodegen generate` writes `Kinwall.xcodeproj` (not committed) |

## Test the shared core

```bash
cd KinwallKit && swift test
```

With a throwaway local server, the live test also pairs and exercises chores and lists:

```bash
cd ../kinwall/server && DATA_DIR=$(mktemp -d) ADMIN_API_KEY=test-admin-key PORT=8177 npm start
cd KinwallKit && KINWALL_TEST_URL=http://127.0.0.1:8177 KINWALL_TEST_ADMIN_KEY=test-admin-key swift test
```

If `swift test` fails to code-sign with "resource fork, Finder information, or similar detritus not allowed", build outside `~/Documents`: `swift test --scratch-path /tmp/kinwallkit-build`.

## Build the apps

```bash
brew install xcodegen
xcodegen generate
open Kinwall.xcodeproj
```

## Install on your own devices

Sign in to Xcode with your Apple ID (**Xcode → Settings → Accounts**), pair the iPhone or iPad (by cable once, then Wi-Fi works) and turn on **Developer Mode** on it. Then:

```bash
TEAM=<your team ID> scripts/install-device.sh
```

- **Free Apple ID:** the first time, trust your developer account on the device (**Settings → General → VPN & Device Management**). The build stops opening after 7 days; run the script again to renew it.
- **Apple Watch:** the Watch app comes inside the iPhone app. For a development build the Watch has to be paired with Xcode too (it connects over the network, so a firewall blocking incoming connections stops it). Then install it from the iPhone's **Watch** app → **Available Apps**.
- **Paid membership:** `TEAM=<team ID> scripts/testflight.sh` uploads a TestFlight build instead.

## License

[AGPL-3.0](LICENSE), like Kinwall itself. Kinwall is built by John Duprey with Claude Code, with UI/UX design decisions by Ashley Duprey.
