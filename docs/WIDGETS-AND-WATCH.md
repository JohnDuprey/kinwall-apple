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
| **List count** (circular) | Open items on Groceries | Later |
| **Points** (circular) | My points this week | Later |

### StandBy and nightstand

The small widgets work in StandBy with no extra work. The Family photo and Now & Next widgets suit a charging iPhone on the kitchen counter.

### Controls (Control Center, Lock Screen, Action button)

| Control | What it does | Tag |
|---|---|---|
| **Add to Groceries** | Opens a one-line quick-add, with dictation | Later |
| **Open the Board** | Opens the app on the Board | Later |

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
| **Groceries** open count | Later |
| **Points** this week | Later |

### Watch-only touches

| Idea | Tag |
|---|---|
| **Double tap** (Series 9 and later) ticks off the top chore or list item on screen | Later |
| **Haptic transition warnings:** a tap on the wrist 10 minutes before the next event, like the wall's transition warnings, from local notifications | First |
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
| **Spotlight** | Lists and chores searchable from the Home Screen | Later |
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
- **Siri and Shortcuts:** Add to a list ("Add to my Kinwall list"), What's next, and Complete a chore, as App Shortcuts that run without opening the app. They show up in the Shortcuts app, but in the iOS 27 Simulator running one fails inside the system ("Couldn't find AppShortcutsProvider") even though the app's own lookup of that type succeeds. Check on a real iPhone. An Anyone chore completed by voice credits nobody in particular for now.
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
