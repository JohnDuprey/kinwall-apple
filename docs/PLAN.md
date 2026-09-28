# Kinwall mobile (iPhone, iPad, Apple Watch and Android): project plan

Open source, not released yet. Nothing here ships to the App Store until there's a paid Apple Developer Program membership; until then the apps run in the Simulator and, signed with a free Apple ID, on our own devices.

**Not enrolled yet.** Builds use a free Apple ID and expire after 7 days. TestFlight (`scripts/testflight.sh`) comes with the paid membership.

**Update 2026-09-27: React Native (Expo), and Android.** The phone and tablet app is now one Expo app for iOS and Android (`src/`), replacing the SwiftUI frame. It does what the Swift frame did: the address screen, OAuth in the system's auth sheet (`expo-web-browser`) or pairing, the web view with the same in-app flags, widget links (`family.kinwall.app:/open?to=…`), local reminders and background refresh, the theme-colored status bar. The iOS widgets, the Watch app, complications and Siri stay Swift on `KinwallKit`, added to the generated Xcode project by `@bacons/apple-targets` and `plugins/withKinwallNative.js`, and still read the widgets' key from the shared Keychain group `family.kinwall.shared`. XcodeGen and `project.yml` are gone. Android gets the same shell, a notification channel for reminders, the back button stepping back through the web app, and a home-screen widget (now and next, chores left). **Wear OS comes later** (M8).

## Goal

Native apps for the family who already use Kinwall. On iPhone and iPad the app shows **Kinwall's own web app** in a native frame, so every screen and feature is there from day one and there's one UI to maintain. Native code does what a web page can't: widgets and complications, the Apple Watch app, Siri and Shortcuts, and (with a paid membership) push notifications.

## What we can and can't do without a paid membership

| | Free Apple ID ("Personal Team") | Paid membership |
|---|---|---|
| Simulator (iPhone, iPad, Watch) | Yes, unlimited | Yes |
| Run on our own iPhone, iPad and paired Watch | Yes, from Xcode. The signature expires after **7 days**; reinstall from Xcode to renew | Yes, a year |
| Widgets and watch complications (WidgetKit) | Yes | Yes |
| Siri and Shortcuts (App Intents) | Yes | Yes |
| Share extension (imports a shared recipe link; shared Keychain group, no App Group) | Yes | Yes |
| **App Groups** (app and widget share storage) | No | Yes |
| **Push notifications** (APNs) | No | Yes |
| iCloud, Sign in with Apple, Associated Domains (passkeys, universal links) | No | Yes |
| TestFlight, App Store | No | Yes |

**Design consequences:**

- **Signing in:** the app uses Kinwall's existing TV-style pairing. It shows a 6-digit code, and an admin approves it under **Settings → Access → Displays**. The app gets its own display key, stored in the Keychain. No passkeys yet, since they need Associated Domains.
- **Widgets:** each widget fetches its own data with the same key. Sharing the key between the app and its widget needs a shared Keychain access group. Whether a Personal Team allows that is **to be verified in M3**. If it doesn't, the widget pairs separately.
- **Freshness:** without push, the apps poll `GET /api/rev` (as the web app does, every 30 s while open) and use background app refresh and WidgetKit timelines. Real-time push waits for the paid membership (M6).

## Signing in, and why not passkeys

Passkeys are tied to a website's domain. Inside an app's web view they only work for domains the app declares ahead of time through Associated Domains. That needs the paid membership, and even then it can only cover domains we know in advance, like `*.kinwall.family`. A self-hosted server on its own domain can never be listed. So:

- **Sign in (built):** the app opens the server's OAuth consent screen in a Safari sheet (`ASWebAuthenticationSession`). That's Safari's own context, so a passkey works on any domain, self-hosted included. The admin picks full or everyday access, and the app receives a code on its `family.kinwall.app:/oauth` link and swaps it for keys. Access keys last an hour and the app refreshes them ahead of time; refresh tokens last 90 days and rotate. The app shows under Settings → Access → Connected apps, and **Sign out** revokes it. No paid membership needed.
- **Pair with a code (built, the fallback):** for a child's phone or a wall iPad. The app shows a code and an admin approves it.
- **Admin steps that ask for the passkey again** (calendar accounts, API keys, webhooks) still happen in Safari: the web view itself can't use passkeys.
- **Hosted, with the paid membership:** Associated Domains for `*.kinwall.family` could also make passkeys work directly in the app's web view.

## No passkey yet (built)

| Situation | What happens |
|---|---|
| **Brand-new server,** not set up yet | The consent link runs the setup wizard in the same Safari sheet, where creating a passkey works, then continues to approval |
| **Set up, but no passkey here** | **Use a recovery code** on the consent screen. After that, **Create a passkey** is offered before **Allow** |
| **Not an admin** (a child) | **Pair with a code**, or an admin approves in the sheet on the child's phone |

## Architecture

- **KinwallKit** (Swift package, done in M0) holds the API client, models, pairing, Keychain storage and household dates. It has no UI and is tested on macOS with `swift test`, including a live test against a local Kinwall server.
- **Kinwall** is one Expo (React Native) app for iPhone, iPad (iOS 17+) and Android: a native frame around the household's own Kinwall web app, full screen. It opens on the web app's pairing screen; once paired, the frame copies the key into the Keychain for the widgets, Watch and Siri, so there's one pairing. The web app gets a flag telling it it's inside the app (`window.kinwallNative`, a `KinwallApp/` user agent, and `<html data-native>`). Inside the app it hides the Add to Home Screen card, explains that push needs Safari for now, offers **Pair this app** instead of passkey sign-in, and drops the gap it keeps under the status bar, which the app hides.
- **Kinwall Watch** is a watchOS 10+ app that talks to the server directly over Wi-Fi or the iPhone's connection. It's paired by handing over the phone's connection with WatchConnectivity, so there's no code to type on a watch.
- **Kinwall Widgets** is a WidgetKit extension for the Home Screen, Lock Screen, StandBy and watch complications.
- **The projects** are generated by `npx expo prebuild` from `app.json`, the config plugins and `targets/*/expo-target.config.js`, so neither `.pbxproj` nor Gradle files are committed.
- **The native parts** (widgets, Watch, Siri) use KinwallKit and keep a small cache so they show the last known state offline. Their look follows the household's color scheme from `/api/settings`.

## Milestones

### M0: Foundation (done)
- [x] Private repo, plan, KinwallKit with the client, models, pairing, Keychain store and household dates
- [x] Unit tests and a live pairing, chores and lists test against a real server (7/7 passing)
- [x] The iOS app, watch app and widget targets (first with XcodeGen, now generated by Expo prebuild)
- [x] Build every target for the Simulator

### M1: The iPhone and iPad app (web UI in a native frame)
- A web view frame (`react-native-webview`), full screen, loading the household's Kinwall URL. The first run asks for the address: hosted `*.kinwall.family` or a self-hosted URL.
- Pairing happens in the web app's own pairing screen. Once paired, the frame reads the key and saves it to the Keychain for the native parts.
- The status bar and background follow the page's `theme-color`, and the safe areas match the installed web app.
- Links to other sites open in Safari. Photo uploads and the file picker work, and so do downloads (the photo zip).
- **Web app changes** (in the `kinwall` repo): detect the frame (a user-agent suffix, or a flag the frame sets), then hide the Add to Home Screen card, the web push settings and **Clear cache and reload**.
- **Notifications:** the frame can't receive web push, since Apple only allows it for Home Screen web apps. Until M6, the Notifications card says so and points to the bell feed.

### M2: iPad wall mode
- Keep the screen awake while the app is open, plus a Guided Access how-to for a kiosk-style wall. Everything else already lives in the web app: the Board, the idle reset, quiet hours and the screensaver.

The feature menu for M3 to M5 is in [WIDGETS-AND-WATCH.md](WIDGETS-AND-WATCH.md).

### M3: Widgets
- Now/Next (small and medium), today's chores left (with interactive tick-off via App Intents), a list (for example Groceries), Lock Screen and StandBy variants
- Verify whether shared Keychain access works on a Personal Team; if not, a widget pairing flow

### M4: Apple Watch
- Hand the connection over from the iPhone (WatchConnectivity)
- My chores (tick, with "Who did it?" via the watch's family picker), Groceries (tick, add by dictation), Now/Next
- Complications: next event, chores left

### M5: Siri and Shortcuts
- "Add milk to Groceries", "What's next?", "Mark Take out trash done", "How many points does Maya have?"
- Spotlight for lists and chores

### M6: When there's a paid membership (not enrolled yet)
- **APNs push:** the server gains an APNs sender beside web push, using the same notification preferences
- **App Groups** for the app and widgets (retire any workaround from M3)
- **Passkeys and universal links** (Associated Domains on `kinwall.family`)
- TestFlight for the family, then an App Store listing: privacy manifest, screenshots, review notes (demo server)

### M7: Android (in progress)
- [x] The shared Expo shell: address screen, OAuth or pairing, web view, deep links, reminders on their own notification channel, the back button through web history
- [x] A home-screen widget (now and next, chores left) rendered from JavaScript with `react-native-android-widget`
- [ ] Build and test on an emulator and a phone (needs JDK 17 and the Android SDK)
- [ ] Play Console listing and internal testing track (EAS `preview` gives an installable APK meanwhile)
- [ ] The web app marks itself `data-native="ios"` inside either app; give Android its own value if styles need to differ

### M8: Wear OS (later)
- A watch app like the Apple Watch one: Now/Next, my chores, Groceries, and tiles and complications. Native Kotlin (Compose for Wear OS), with the key handed over from the phone app over the Wearable Data Layer.

## Server work (in the `kinwall` repo)

None is needed for M0 to M5; everything above uses existing endpoints. Nice-to-haves, as they come up:

- **Pairing:** a `kind: "ios" | "watchos"` hint on `/api/pair`, so Settings → Access → Displays can show "iPhone app" instead of a generic display.
- **Checklist and snapshot endpoints** are already there; the Board has `GET /api/board`.
- **M6:** APNs delivery in `notify.ts`, plus device tokens stored like web push subscriptions.

## Action items

**Claude:**

1. **Done:** repo, plan, KinwallKit and tests; M1 to M5 in Swift; the move to Expo with the native targets kept.
2. M7: build and test Android once a machine has JDK 17 and the Android SDK.
3. M8: Wear OS.

**You:**

1. **For Android:** a machine with JDK 17 and the Android SDK (Android Studio), or an Expo account for EAS builds.
2. **To run on your own iPhone, iPad or Watch:**
   - In Xcode, go to **Settings → Accounts** and sign in with your Apple ID. This creates the free Personal Team.
   - Turn on **Developer Mode** on each device: **Settings → Privacy & Security → Developer Mode**.
   - Expect to reinstall from Xcode every 7 days.
3. **Before M1 ships to the family's phones:** decide whether the apps pair with your hosted household, a local server, or both. The app supports any URL either way.
4. **Later:** the Apple Developer Program ($99/year) unlocks M6.

## Risks

- **7-day expiry** on a Personal Team makes daily use by the family awkward. Treat M1 to M5 as a preview until M6.
- **No push until M6:** on iPhone, the installed web app gets notifications and the native app doesn't. Until then the native app's reasons to exist are widgets, the Watch and Siri.
- **App Store review (M6):** Apple rejects apps that only frame a website (guideline 4.2). Widgets, the Watch app, Siri and push are what make this more than that, so they ship before a submission.
- **Widget and app key sharing** may not work on a Personal Team (see M3).
- **Polling costs battery** if overdone. Poll `rev` only while the app is in the foreground, and rely on timelines otherwise.
- **API drift:** KinwallKit decodes only the fields it uses. The live test catches renamed or reshaped fields, which is how M0 caught `GET /api/lists/{id}` wrapping the list in `list`.
