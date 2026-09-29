# Publishing to the App Store and Google Play

How a release of the Kinwall app gets into the stores. The unsigned test builds on GitHub Releases
are separate (see the README); store builds are signed with the publisher's accounts.

Identifiers: iOS bundle ID and Android package are both `family.kinwall.app`.

## Apple App Store (iPhone, iPad, Apple Watch)

**Once**

1. Apple Developer Program membership (the individual enrollment).
2. In App Store Connect, create the app with bundle ID `family.kinwall.app` (register the App IDs for
   the widgets, share extension and Watch app too; Xcode or EAS can do this).
3. Fill in the app record: name, subtitle, description, keywords, support and privacy policy URLs,
   category (Productivity or Lifestyle), age rating questionnaire (4+ expected), and the App
   Privacy "nutrition label" (match `docs/PRIVACY-MANIFEST.md`: family data sent to the family's own
   server, linked to the user, not used for tracking).
4. Export compliance: the app only uses standard HTTPS, so it's exempt; set
   `ITSAppUsesNonExemptEncryption` to `false` in the iOS config so each build doesn't ask.
5. Signing: let EAS manage certificates and profiles (`eas credentials`), or Xcode's automatic
   signing with the paid team.

**Each release**

1. Build: `eas build --platform ios --profile production` (or Xcode → Product → Archive). Build
   numbers must go up; see the release workflow's versioning rule.
2. Upload: `eas submit --platform ios` (or Xcode Organizer → Distribute App → App Store Connect).
3. TestFlight: the build appears after processing; test internally, then add external testers
   (external testing needs a short beta review).
4. Submit for review in App Store Connect with:
   - screenshots (6.9" and 6.5" iPhone, 13" iPad, Apple Watch; generated from the demo),
   - review notes: "No account needed: tap **Try the demo** on the first screen" (the demo family),
     and a line on what the widgets, Live Activities and Watch app do,
   - "What's New" text from the changelog.
5. After approval, release manually or automatically.

Things review looks at for Kinwall: guideline 4.2 (more than a website; the native features cover
it), account deletion info (in iPhone Settings → Kinwall), no purchases or prices in the app
(payments are web only), and the push entitlement only in builds that use push (`KINWALL_PUSH=1`).

## Google Play (Android)

**Once**

1. A Google Play developer account (one-time fee; identity verification).
2. **Personal accounts must run a closed test first:** new personal developer accounts need a closed
   test with at least 12 testers opted in for 14 days in a row before they can publish to
   production. Plan for this; an organization account doesn't have the rule.
3. In Play Console, create the app with package `family.kinwall.app`.
4. Turn on Play App Signing (Google holds the app signing key; you keep an upload key, which EAS can
   manage with `eas credentials`).
5. Store listing: title, short and full description, icon, feature graphic, phone and tablet
   screenshots, privacy policy URL.
6. App content forms:
   - Data safety (match the iOS privacy label),
   - Content rating questionnaire,
   - Target audience: a family organizer used by parents and kids; if under-13s are a target, the
     Families policy applies, so answer carefully,
   - Health apps declaration (medications, check-ins and the Health tracker count),
   - Exact alarms: the app uses `SCHEDULE_EXACT_ALARM` for reminders and countdowns; calendar and
     reminder apps qualify, and Play may ask for the justification,
   - Ads: none.

**Each release**

1. Build an Android App Bundle: `eas build --platform android --profile production` (AAB, not APK;
   `versionCode` must go up).
2. Upload: `eas submit --platform android`, or upload the AAB in Play Console to a track.
3. Tracks: internal testing, then closed testing, then production (staged rollout is a good
   default).
4. Release notes from the changelog; submit for review (usually hours to a few days).

## Not in the stores

- Unsigned iOS and debug-signed Android builds on GitHub Releases, for testers and self-hosters.
  The debug-signed APK can't update a Play Store install, and the reverse.
