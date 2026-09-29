# Widgets, Apple Watch and Siri: feature ideas

A menu for M3 (widgets), M4 (Watch) and M5 (Siri), built on things Kinwall already does. Each idea is tagged:

- **First:** worth doing in the first pass.
- **Later:** a good follow-up.
- **Paid:** needs the paid Apple Developer membership (M6).

## Things that shape every feature

- **Widgets and the Watch get their own key.** An OAuth key that refreshes and rotates can't safely be shared between the app, a widget and a watch, because two refreshers would end the grant. Instead, the signed-in app creates a separate everyday-access key for its widgets ("Widgets on this iPhone") and one for the Watch. Each can be revoked on its own under Settings → Access. This needs a small server route that lets an OAuth-signed-in app mint a display key for itself.
- **Sharing that key with the widget** needs a shared Keychain group. Whether a free Personal Team allows that is still to be confirmed (see PLAN.md). If it doesn't, each widget pairs itself once with a code.
- **Local notifications work without the paid account.** The app can schedule reminders on the device from the data it already has: event reminders, leave-by times and the chore nudge. On iPhone, that gives the app real reminders before APNs push exists. The Watch mirrors iPhone notifications automatically.
- **Widgets update on a budget,** about every 15 to 60 minutes, plus right away after a tap inside the widget. Countdowns ("in 12 min") use the system's live timer text, so they tick without refreshes.
- **"Who am I" on a device.** A watch, or a widget set to one person, knows whose chores to show and who gets the points for an Anyone chore. That removes the "Who did it?" question wherever the answer is obvious.

## Widgets (iPhone and iPad)

### Home Screen

| Widget | Sizes | What it shows | Tag |
|---|---|---|---|
| **Now & Next** | Small, medium | What's on now, what's next, and a live "leave in 12 min" countdown. Surfaces itself in the Smart Stack as leave-by nears. | First |
| **Today** | Medium, large | A small Board: today's events, chores left per person, what's due. | First |
| **Chores** | Small to large, interactive | Everyone, one person (with or without Anyone chores), or only Anyone chores, with a tap to tick off. Set to a person, it credits them for Anyone chores; otherwise an Anyone chore opens the app to ask who did it. A chore with an open checklist opens the checklist in the app. The small size uses the chore's emoji as the checkbox so titles get two lines. | First |
| **List** | Medium, large, interactive | A chosen list, like Groceries: tick items off in the widget. **Add** opens a quick-add in the app. | First |
| **Leaderboard** | Small, medium | This week's points and streaks. Motivating on a kid's iPad. | Later |
| **Family photo** | Small to large | A rotating picture from the family album, like the Board's photo card. Great in StandBy. | Later |
| **Countdown** | Small | Days until a chosen event or the next birthday ("Beach trip in 12 days"). | Later |
| **Week** | Large, extra large (iPad) | The next seven days as a list. | Later |

### Lock Screen

| Widget | What it shows | Tag |
|---|---|---|
| **Next event** (inline and rectangular) | "Soccer · 4:00 · leave 3:40" | First |
| **Chores left** (circular) | A ring filling as today's chores get done | First |
| **Take now** (circular, rectangular, inline) | Medicines due now: how many, and whose. Names stay "Medicine" unless the widget's **Show medicine names** is on and the server shares names with this device (a person's own device, or a wall with names on) | Built |
| **List count** (circular) | Open items on Groceries | Later |
| **Points** (circular) | My points this week | Later |

### StandBy and nightstand

**Clock & next** (small) is made for StandBy: a big clock (one timeline entry a minute from a single fetch) and what's next, with the leave-by time. The other small widgets work in StandBy too. The Family photo and Now & Next widgets suit a charging iPhone on the kitchen counter.

### Controls (Control Center, Lock Screen, Action button)

| Control | What it does | Tag |
|---|---|---|
| **Add to Groceries** | Opens Groceries in the app, at its add field (a control can't take typing) | Built |
| **Start shopping** | Opens shopping mode on Groceries | Built |
| **Night screen** | Opens the app on the dim night clock | Built |

Built 2026-09-29 in `targets/widgets/Controls.swift` (iOS 18 and later; on iOS 17 they aren't offered). Each runs an open-the-app intent from `native/ios/OpenIntents.swift`, compiled into the app and the widget extension, so iOS runs it in the app. They work from Control Center, the Lock Screen's control slots and the Action button. Checked in the Simulator: all three are offered under Kinwall in Control Center, and Night screen opens the night clock. A one-line quick-add without opening the app would need Kinwall's own small add screen; the web app's list is the add screen for now.

### Live Activities

Built (2026-09-29), in `targets/widgets/LiveActivities.swift`, started by the app from the web app's messages (`modules/kinwall-native/ios/LiveActivities.swift`; the web app decides what they say, `web/src/liveActivity.ts` in kinwall). One `KinwallActivityAttributes` type for all three (`modules/kinwall-native/ios/KinwallActivityAttributes.swift`, compiled into the widget extension too). No Kinwall setting: iPhone **Settings → Kinwall → Live Activities** turns them off, and the web app's Notifications section says which.

| Activity | What it does | Needs |
|---|---|---|
| **Cooking timer** | Starts with a step timer in cooking mode: recipe, timer name and step, a countdown (`Text(timerInterval:)`), "+1 more". When it's up it says "Done: Chicken" (it goes stale at the timer's end, so no update is needed); gone when the timer is dismissed or cooking mode closes. | Nothing: local |
| **Shopping trip** | Starts with a trip (Shop, or shopping mode): the store and how many are left on top, the item to get now in large type, and under it where that item is and what's after it ("Dairy · then Dishwasher tablets (Aisle 17)", "then Milk (same aisle)", or "Dairy · last one!"), in walking order. A long next item is shortened, never the aisle. **Got it** ticks that item (`GotItIntent`, `native/ios/LiveActivityIntents.swift`) with the widgets' own key from the shared Keychain group, then moves on to the next of the five items it carries; **Open** opens shopping mode (`family.kinwall.app:/open?to=lists/<id>/shop`). The page updates it on every change; Checkout or End ends it. | Nothing: the shared Keychain group, no App Group |
| **Leave by / start prep by** | The device's person's next leave-by or start-prep time (a meal's event), from their first transition reminder until the event starts: a varied headline ("Sam, leave for Piano Lesson at 10:55 AM 🚙") and a countdown, then "Leave now" once it's time (stale date). Only on a phone that belongs to someone with transition reminders on and notifications allowed. | Local while the app is open; Apple push (paid) while it's closed |

Checked in the iOS 27 Simulator (iPhone 17 Pro) with the demo: all three start and show on the Lock Screen and in the Dynamic Island (compact, minimal, expanded), countdowns tick, and **Got it** moves the trip on. In that Simulator iOS runs Got it in the widget extension rather than the app, so both copies of the intent do the whole job. `xcrun simctl push` delivered a push-to-start payload only as a plain notification (no Live Activity), so push-to-start is checked by the server's tests, not end to end.

## Apple Watch

### The app

| Screen | What it does | Tag |
|---|---|---|
| **Today** | Now & Next with the leave-by countdown, then the rest of today. Tap an event for its details, and its location opens Maps. | First |
| **My chores** | This watch's person's chores for today. Tap to tick off. Anyone chores count for them. Checklist steps can be ticked one by one. | First |
| **Lists** | Groceries and others. Big rows to tick off while shopping, with the phone in a pocket. Add by dictation or Scribble. Works offline and syncs when back in reach. | First |
| **Points** | My points, streak and sticker balance. | Later |
| **Messages** | The notification feed (the bell), including family messages. | Later |
| **Family** | Who has what today, one line per person. | Later |

### Complications and the Smart Stack

| Complication | Tag |
|---|---|
| **Next event** with the leave-by countdown, surfacing in the Smart Stack as it nears | First |
| **Chores left** as a gauge | First |
| **Take now:** how many medicines are due (circular, inline, corner), never their names | Built |
| **Groceries** open count | Later |
| **Points** this week | Later |

### Watch-only touches

| Idea | Tag |
|---|---|
| **Double tap** (Series 9 and later) ticks off the top chore or list item on screen | Later |
| **Haptic transition warnings:** a tap on the wrist before the next event, like the wall's transition warnings, from local notifications | Built |
| **A child's watch without an iPhone** (Apple's Family Setup): the watch pairs itself with a code an admin approves, the same flow as a wall display. Chores, points and Now & Next, all on the wrist. | Later |

## Siri, Shortcuts and Spotlight (App Intents)

These run on iPhone, iPad and Watch, and power the interactive widgets too.

| Intent | Example | Tag |
|---|---|---|
| **Add to a list** | "Add eggs to Groceries in Kinwall" | First |
| **What's next** | "What's next on Kinwall?" | First |
| **Complete a chore** | "Mark Take out trash done" | First |
| **Points** | "How many points does Maya have?" | Later |
| **What's on** a day | "What's on Kinwall tomorrow?" | Later |
| **Spotlight** | Recipes, lists and contacts searchable from the Home Screen | Built |
| **Action button** (iPhone 15 Pro and later, Watch Ultra) | Mapped to "Add to Groceries" | Later |

## Status

- **Built and checked in the Simulator:**
  - Now & Next, including the Lock Screen versions.
  - Today.
  - Chores left, as a ring.
  - Chores (interactive): Person (Everyone or one person), Include Anyone chores, and Only Anyone chores, which hides the other two. Tapping a chore completes it on the server. Set to a person, it credits them for Anyone chores; otherwise an Anyone chore opens the app on "Who did it?". A chore with an open checklist opens that checklist in the app.
  - List (interactive).
  - The widgets' own key, created with the server's device-key route and revoked on sign-out.
  - The demo: while **Try the demo** is open, every widget shows built-in sample data for the demo family, marked Demo (src/demo.ts sets `SharedKeychain.demoStore`; a real family's key always wins). Tapping a sample chore or item opens the demo instead of ticking it. Not yet checked on a device.
- **Widget settings use only strings and switches.** In the Simulator, a custom AppEntity or AppEnum saved in a widget's settings read back empty, so the person and the list are saved as ids chosen from a dynamic options list. Switches can hide rows (Only Anyone chores hides Person); a string or enum choice can't be relied on for that.
- **Event reminders on the device:** the app schedules each event's reminders (its own times, or the household default) as local notifications for the next 48 hours, with the same wording as the server's push, and a tap opens the event. It refreshes when the app opens, goes to the background, and a few times a day in the background. Checked in the Simulator: permission is asked right after sign-in and a reminder arrives on time with the server's wording. Every event is included for now; the per-person filter that web push has is a follow-up.
- **Watch app (first pass):** the iPhone app creates an "Apple Watch" key and sends it over WatchConnectivity; the Watch keeps it in its own Keychain. Screens: Today (Now & Next with the countdown, then later today), My chores (asks whose Watch it is once, Anyone chores count for that person, haptic on tick), Lists (tick items, add by dictation or Scribble). Checked in the Simulator: the key arrives from the iPhone, Today shows live data, a chore ticked on the Watch is credited to the Watch's person, and list items tick off.
- **Watch complications:** Next event (rectangular with the leave-by countdown, inline, corner) and Chores left (circular gauge), reading the Board with the Watch's key from the shared Keychain group. Built and embedded; not yet placed on a watch face in the Simulator.
- **Siri and Shortcuts (built 2026-09-29):** App Shortcuts that work without setup, in `native/ios/SiriIntents.swift`, with lists, people, today's chores and stores as entities Siri can match in a phrase:
  - **Add to a list:** "Add to Groceries in Kinwall" (Siri asks what to add; Groceries unless you name another list).
  - **What's on today:** "What's on today in Kinwall" says what's left of today and how many chores are left, and shows it as a list.
  - **What's next**, as before.
  - **Start shopping:** "Start shopping in Kinwall" or "Start shopping at Neighborhood market in Kinwall" opens shopping mode on Groceries. The store rides along as `?store=` (the web app asks for the store until it reads that).
  - **Mark a chore done:** "Mark Water plants done in Kinwall", with an optional **Who did it** that gets the points for an Anyone chore. The server's rules for the widgets' key apply: a device that belongs to one person can only tick theirs, and Kinwall's refusal is read out.
  - **Start the night screen:** "Start the Kinwall night screen" opens the app on the dim night clock (the event the header's 🌙 button sends).

  They run in the app's process with the widgets' key; the ones that open the app hand their link to the web app through the native module (`PendingLink`), so one that launches the app isn't lost. In the demo they answer from the demo family and save nothing. Checked in the iOS 26.5 Simulator (iPhone 17 Pro): What's on today, Mark a chore done (with its chore and person pickers) and Night screen. The earlier "Couldn't find AppShortcutsProvider" came from the Simulator build being signed ad hoc, with no team; `scripts/sign-simulator.sh` re-signs it (README).
- **Take now and Clock & next (built 2026-09-29):** Take now reads `GET /api/medications/due` with the widgets' key every 15 minutes; the Home Screen size has **Taken**, which marks the first dose (`MarkDoseIntent`). The medicines feature turned off (404) shows "Nothing due". Checked in the Simulator with the demo: both on the Home Screen, and Take now and Chores left on the Lock Screen.
- **Watch: Take now, transition warnings, meds complication (built 2026-09-29):**
  - **Take now** is a fourth page in the Watch app: the doses due now with **Taken** and **Snooze** (10 minutes), straight to the server with the Watch's key (`POST /api/medications/{id}/doses`). A person's own Watch shows their medicines' names, as the server allows; otherwise "Medicine".
  - **Transition warnings** (`targets/watch/Transitions.swift`): the Watch's person (picked on My chores) gets their transition reminders as local notifications, computed on the Watch from their next 24 hours of events (`KinwallKit TransitionWarnings`, the server's rule: before the leave-by time when they have leave-by on, else before the start). Rescheduled when the app opens and on background refresh about every 30 minutes. Limits: no push, so an event added elsewhere is only covered after the next refresh; watchOS keeps 64 pending notifications (48 used); in the background watchOS plays its own notification tap, and the distinct pattern (three rising taps) plays only while the app is frontmost; meal prep times aren't in the events API, so a meal counts from its start.
  - **Take now complication:** the count of doses due, never names.
- **Spotlight (built 2026-09-29):** the family's recipes, lists and contacts, by name with a short line ("Recipe · 35 min · …", "Shopping list · 12 left", "Contact · Grandparent"), never notes, phone numbers, addresses or health entries. `src/spotlight.ts` fetches them with the widgets' key when the app opens or comes back (at most every 10 minutes) and hands them to `modules/kinwall-native/ios/Spotlight.swift`, which replaces the app's items; sign-out clears them. The demo shows a few of the demo family's. Each item's identifier is its app link, so a tap opens its page (`native/ios/AppHooks.swift`). The web app opens Lists on the list (`?list=`); a recipe or contact opens Meals or Contacts until it reads `?recipe=` and `?contact=`. Checked in the Simulator: "Rosa" finds Grandma Rosa and the tap opens Contacts.
- **Next:** install on a real iPhone and Watch; check Siri, reminder taps and complications there.

## A sensible first pass

- **M3 (iPhone widgets):**
  - Now & Next and Today.
  - Interactive Chores and List widgets.
  - Next event and Chores left on the Lock Screen.
  - Local notifications for reminders and leave-by.
- **M4 (Watch):**
  - Today, My chores and Lists.
  - Next event and Chores left complications.
  - Haptic transition warnings.
- **M5 (Siri):**
  - Add to a list, What's next, and Complete a chore.
  - These double as the actions behind the interactive widgets.
