// Android: the leave-by and start-prep countdowns scheduled ahead, so they show even with the app
// closed and no push (modules/kinwall-native/android Countdowns.kt sets an exact alarm at each
// warning). The same rules as kinwall's web/src/liveActivity.ts leaveByActivity and
// transitions.ts warningTimes, applied to the next day's events; keep them in step. No React
// Native imports, so test/leaveBy.test.ts runs it under plain node.

const MIN = 60_000
/** After the time, the countdown stays ("Time to leave") until the event starts, and at least this long. */
const GRACE_MIN = 5
const HORIZON = 24 * 60 * MIN
/** Two alarms each (the warning and the time): plenty for a day, well under Android's limits. */
const CAP = 20

export type Transitions = { on: boolean; minutes: number[]; repeat?: { every: number; within: number } | null; leaveBy?: boolean }
export type LeaveByPerson = { id: string; transitionReminders?: Transitions | null }
/** GET /api/events: `prepAt` and `cookId` on a meal's event, `leaveAt` with travel time. */
export type LeaveByEvent = { id: string; title: string; start: string; allDay: boolean; memberIds?: string[]; leaveAt?: string | null; prepAt?: string | null; cookId?: string | null }
/** Times in ms. `activity` is the web's name for it, so the page's own countdown replaces this one. */
export type LeaveByAlarm = { activity: string; eventId: string; title: string; prep: boolean; warnAt: number; at: number; endsAt: number }

/** Minutes before the time of the first warning, or undefined when they get none. */
export function firstWarning(t: Transitions | null | undefined): number | undefined {
  if (!t?.on) return undefined
  const all = new Set(t.minutes)
  if (t.repeat && t.repeat.every > 0) for (let m = t.repeat.every; m <= t.repeat.within; m += t.repeat.every) all.add(m)
  const valid = [...all].filter((m) => m >= 1 && m <= 120)
  return valid.length ? Math.max(...valid) : undefined
}

/** This person's countdowns that haven't ended and warn within the next day, soonest first. Their
 * events are the ones tagged with them or nobody; a meal's prep only for its cook when it has one. */
export function leaveByAlarms(events: LeaveByEvent[], me: LeaveByPerson, now: number): LeaveByAlarm[] {
  const cfg = me.transitionReminders
  const first = firstWarning(cfg)
  if (!cfg || !first) return []
  const mine = (ids: string[] = []) => ids.length === 0 || ids.includes(me.id)
  return events.flatMap((e) => {
    const prep = !!e.prepAt
    const lead = e.prepAt ?? e.leaveAt
    if (e.allDay || !lead || (!prep && !cfg.leaveBy)) return []
    if (!(prep && e.cookId ? e.cookId === me.id : mine(e.memberIds))) return []
    const at = Date.parse(lead), start = Date.parse(e.start)
    if (Number.isNaN(at) || Number.isNaN(start)) return []
    const warnAt = at - first * MIN, endsAt = Math.max(start, at + GRACE_MIN * MIN)
    if (endsAt <= now || warnAt > now + HORIZON) return []
    return [{ activity: `leaveBy:${e.id}@${new Date(start).toISOString()}`, eventId: e.id, title: e.title, prep, warnAt, at, endsAt }]
  }).sort((a, b) => a.warnAt - b.warnAt).slice(0, CAP)
}
