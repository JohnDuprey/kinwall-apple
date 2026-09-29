# Changelog

## [1.0.0](https://github.com/JohnDuprey/kinwall-mobile/compare/v0.1.0...v1.0.0) (2026-09-29)

The first release of the Kinwall app. It wraps your family's Kinwall (self-hosted, or any Kinwall
server) in a native app, and adds the things a web page can't do: widgets, Live Activities, Siri,
a Watch app and more. No account needed to look around: tap **Try the demo** on the first screen.

### The app
* **Sign in to your family's Kinwall**, or **Try the demo** with a sample family (widgets and
  reminders included), right from the first screen.
* **Starts in your family's colors**, light or dark, with no white or peach flash on launch, and
  no sign-in screen flicker when you're already signed in.
* **Share a recipe to Kinwall** from Safari, Chrome or any app (iOS and Android share sheet): it
  checks the recipe reads correctly and asks before importing.
* Keeps the screen on in shopping mode and while a recipe is open.
* Web links open in an in-app browser; the back button (Android) steps back through Kinwall.

### Live Activities (iPhone) and ongoing notifications (Android)
* **Cooking timers**: the step's timer counts down on the Lock Screen and in the Dynamic Island,
  then says "Done".
* **Shopping trips**: the store, how many are left, the next item and where it is ("Dairy · then
  Dishwasher tablets (Aisle 17)"); tick it off with **Got it** without opening the app.
* **Leave by / start prep by**: a countdown to when you need to leave, or start cooking a meal,
  with friendly, varied reminders.
* **Medicine that's due**: "Still time for Maya's medicine · until 8 PM" with **Taken** and
  **Snooze**. Generic on the Lock Screen unless the device turns names on.
* On Android, leave-by countdowns are scheduled on the phone, so they appear even with the app
  closed.

### Widgets and Controls
* Home Screen widgets for today, chores and lists; **tick a chore or list item right from the
  widget**.
* **Lock Screen widgets**: next event, chores left, and a Take now medicine widget with Taken.
* **Daily check-in widget**: answer "How did you sleep?" and "How are you feeling?" with a tap;
  the evening goal check and "How drained do you feel?" in the evening.
* **Energy battery widget**: today's level and what's behind it (Lock Screen: a gauge only).
* A **StandBy clock** with the next event for a phone charging on the nightstand.
* **Controls** (iOS 18) for Control Center, the Lock Screen and the Action button: Add to
  Groceries, Start shopping, Night screen.

### Siri, Shortcuts and Spotlight (iPhone)
* "Add milk to Groceries", "What's on today?", "What's next?", "Start shopping at the market",
  "Mark Leo's chore done", "Start the night screen".
* Search your family's recipes, lists and contacts from Spotlight; a tap opens them in Kinwall.

### Apple Watch
* Today, your chores, and a **Take now** page with Taken and Snooze.
* **A gentle three-tap buzz** at each transition warning ("leave in 10 minutes").
* One-tap sleep check-in, and complications for the next event, chores left, medicine due and your
  energy battery.

### Privacy
* Health information (medicines, check-ins, the energy battery) stays on the person's own device
  and parents' devices, is generic on the Lock Screen unless you turn names on, and is never on a
  shared wall.
* Privacy manifests for the app and every extension; how to delete your family's data is in
  iPhone Settings → Kinwall.

### Good to know
* These are **test builds** (see "Install a test build" below). The App Store and Google Play
  versions come later.
* Countdowns that start while the app is closed on iPhone, and native push notifications, need the
  store version; everything above works without them.
* The newest features (Live Activities for
  medicine, start prep by, varied reminders) need an up-to-date Kinwall server.
