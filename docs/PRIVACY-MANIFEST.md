# Privacy manifests

Apple wants a privacy manifest (`PrivacyInfo.xcprivacy`) in the app and in each extension. Kinwall's:

| Bundle | Where it comes from | Required-reason APIs | Data collected |
|---|---|---|---|
| The app | `app.json` → `ios.privacyManifests` (Expo writes `ios/Kinwall/PrivacyInfo.xcprivacy`) | File timestamps (C617.1), UserDefaults (CA92.1), system boot time (35F9.1): React Native's own, which it asks the app to declare | See below |
| The Watch app | The same file: Expo adds the app's manifest to the Watch target too, so a second one there would collide | UserDefaults (CA92.1) covers `@AppStorage` (whose Watch it is) | Same as the app |
| Widgets, Controls, Live Activities | `targets/widgets/PrivacyInfo.xcprivacy` | None | None of its own |
| Share extension | `targets/share/PrivacyInfo.xcprivacy` | None | None of its own |
| Watch complications | `targets/watch-widgets/PrivacyInfo.xcprivacy` | None | None of its own |

The Expo modules bring their own manifests in their `_privacy` bundles (expo-application, expo-constants, expo-notifications, expo-task-manager, expo-file-system), and React Native's pods theirs; Xcode merges them into the privacy report. `react-native-webview` and `react-native-safe-area-context` use no required-reason APIs.

## Data collected

What the app sends is the family's own data, to their own Kinwall server. For a self-hosted server that isn't collection by us at all; for hosted Kinwall (kinwall.family) it is, so the app declares it, all **linked to the user**, **not used for tracking**, and only for **app functionality**:

- **Name:** family members' names.
- **User ID:** member and device ids, and the keys the app signs in with.
- **Device ID:** Live Activity push tokens, only in builds with Apple push (`KINWALL_PUSH=1`).
- **Contacts:** the household contacts directory.
- **Health:** the Health tracker, medicines, the daily check-in and the energy battery (encrypted at rest on the server).
- **Photos or videos:** the family photos.
- **Other user content:** events, chores, lists, recipes, notes and journal entries.

Nothing goes to third parties: no analytics, no ads, no tracking domains. The App Store privacy labels should match this list (docs/PLAN.md, App Store readiness).
