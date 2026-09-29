import KinwallNative, { type ActivityToken } from '../modules/kinwall-native'
import { api, type Connection } from './api'

// The Live Activities on iPhone (modules/kinwall-native/ios/LiveActivities.swift draws nothing
// itself; targets/widgets/LiveActivities.swift does): the web app says what to show
// (web/src/native.ts tellAppActivity in the kinwall repo) and WebShell hands it over here. No-ops
// on Android, where the native module is null.

const KINDS = ['cooking', 'shopping', 'leaveBy']
type Colors = { bg: string; fg: string; accent: string } | null

export function showActivity(kind: unknown, payload: unknown, colors: Colors) {
  if (!KinwallNative || typeof kind !== 'string' || !KINDS.includes(kind) || !payload || typeof payload !== 'object') return
  KinwallNative.activitySet(kind, JSON.stringify(payload), colors).catch(() => {}) // a payload the app can't read shows nothing
}
export function endActivity(kind: unknown) {
  if (typeof kind === 'string' && KINDS.includes(kind)) KinwallNative?.activityEnd(kind).catch(() => {})
}
/** Sign-out: nothing of this household stays on the Lock Screen. */
export const endAllActivities = () => { KinwallNative?.activityEnd(null).catch(() => {}) }
/** Ones whose time passed while the app was closed. */
export const endStaleActivities = () => { KinwallNative?.activityEndStale().catch(() => {}) }

/** For the page (window.kinwallNative.liveActivities): allowed in iPhone Settings; null on Android. */
export function activitiesEnabled(): boolean | null {
  try { return KinwallNative ? KinwallNative.activitiesEnabled() : null } catch { return null }
}

// With Apple push (a paid team, docs/PLAN.md) the app gets tokens for the server, which then starts
// a leave-by activity while the app is closed and ends it on time. They're registered with the
// key the page is signed in with (the server keeps them per device), never in the demo, and the
// push-to-start token only while this device would get transition reminders (its person has them
// on and notifications are allowed): otherwise it's taken back.
let device: Connection | null = null
let wanted = false
let start: ActivityToken | null = null
const updates: ActivityToken[] = []
const put = (t: ActivityToken) => device && api(device.baseURL, device.key, 'PUT', 'api/live-activities/tokens', t).catch(() => {})
const flush = () => {
  if (!device) return
  if (start && wanted) put(start)
  while (updates.length) put(updates.shift()!)
}
export function setActivityDevice(c: Connection | null) { device = c; flush() }
export function setLeaveByPush(on: boolean) {
  if (wanted && !on && device) api(device.baseURL, device.key, 'DELETE', 'api/live-activities/tokens', {}).catch(() => {})
  wanted = on
  flush()
}
KinwallNative?.addListener('activityToken', (t) => { if (t.kind === 'start') start = t; else updates.push(t); flush() })
