import * as BackgroundTask from 'expo-background-task'
import * as Notifications from 'expo-notifications'
import * as TaskManager from 'expo-task-manager'
import { Platform } from 'react-native'
import { type EventInstance, events } from './api'
import { widgetConnection } from './sharedKey'

// Event reminders as local notifications (docs/WIDGETS-AND-WATCH.md): the app can't receive the
// server's web push, so it schedules the same reminders itself from the event list, using each
// event's own reminder times (or the household default the server fills in). Rescheduled whenever
// the app opens or goes to the background, and by a background task a few times a day.
const REFRESH_TASK = 'family.kinwall.app.reminders'
const PREFIX = 'rem:'
/** iOS keeps at most 64 pending notifications per app; leave room for anything else. */
const CAP = 60
/** How far ahead to schedule. Refreshes happen well within this. */
const HORIZON = 48 * 3600 * 1000
const CHANNEL = 'reminders'

Notifications.setNotificationHandler({
  handleNotification: async () => ({ shouldShowBanner: true, shouldShowList: true, shouldPlaySound: true, shouldSetBadge: false }),
})

/** Asks once; later calls return the saved answer without a prompt. */
export async function requestPermission(): Promise<void> {
  if (Platform.OS === 'android') await Notifications.setNotificationChannelAsync(CHANNEL, { name: 'Event reminders', importance: Notifications.AndroidImportance.HIGH }).catch(() => {})
  await Notifications.requestPermissionsAsync().catch(() => {})
}

export async function refreshReminders(): Promise<void> {
  const { granted } = await Notifications.getPermissionsAsync()
  const connection = await widgetConnection()
  if (!granted || !connection) return
  const now = Date.now()
  // ponytail: fetch failure keeps the reminders already scheduled; they may be stale until the next refresh.
  const list = await events(connection, new Date(now - 3600_000), new Date(now + HORIZON)).catch(() => null)
  if (!list) return
  const planned = list.flatMap((e) => requestsFor(e, now)).sort((a, b) => a.fire - b.fire).slice(0, CAP)
  const old = (await Notifications.getAllScheduledNotificationsAsync()).filter((r) => r.identifier.startsWith(PREFIX))
  await Promise.all(old.map((r) => Notifications.cancelScheduledNotificationAsync(r.identifier)))
  for (const p of planned) await Notifications.scheduleNotificationAsync(p.request).catch(() => {})
}

/** Sign-out: nothing should fire for a household this device no longer belongs to. */
export async function clearReminders(): Promise<void> {
  const old = (await Notifications.getAllScheduledNotificationsAsync()).filter((r) => r.identifier.startsWith(PREFIX))
  await Promise.all(old.map((r) => Notifications.cancelScheduledNotificationAsync(r.identifier)))
}

// A few times a day, so reminders for events added elsewhere are scheduled even if the app isn't opened.
TaskManager.defineTask(REFRESH_TASK, async () => {
  await refreshReminders()
  return BackgroundTask.BackgroundTaskResult.Success
})
export const scheduleBackgroundRefresh = () => BackgroundTask.registerTaskAsync(REFRESH_TASK, { minimumInterval: 240 }).catch(() => {})

// ---- Building them (mirrors the server's reminder text in server/src/notify.ts) ----

const time = (d: Date) => d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })

function requestsFor(e: EventInstance, now: number): { fire: number; request: Notifications.NotificationRequestInput }[] {
  if (!e.reminders?.length) return []
  // ponytail: all-day events start at midnight in the device's timezone, not the household's; differs only when the phone travels.
  const start = e.allDay ? localMidnight(e.start) : Date.parse(e.start)
  if (Number.isNaN(start)) return []
  const leave = e.remindBeforeLeave && e.leaveAt ? Date.parse(e.leaveAt) : null
  const anchor = leave ?? start
  const timeText = e.allDay ? 'All day' : time(new Date(start))
  const out: { fire: number; request: Notifications.NotificationRequestInput }[] = []
  for (const m of e.reminders) {
    const fire = anchor - m * 60_000
    if (fire <= now || fire > now + HORIZON) continue
    const first = leave != null ? `Leave by ${time(new Date(leave))} for ${e.title} · starts ${timeText}` : `${when(m)} · ${timeText}`
    const body = [first, e.location ? `📍 ${e.location.replace(/\n/g, ', ')}` : null].filter(Boolean).join('\n')
    const route = `calendar?event=${encodeURIComponent(e.id)}&at=${encodeURIComponent(e.start)}` // tap opens this event
    out.push({
      fire,
      request: {
        identifier: `${PREFIX}${e.id}:${e.start}:${m}`,
        content: { title: e.title, body, sound: 'default', data: { route } },
        trigger: { type: Notifications.SchedulableTriggerInputTypes.DATE, date: fire, channelId: CHANNEL },
      },
    })
  }
  return out
}

function when(m: number): string {
  if (m === 0) return 'Now'
  if (m % 60 === 0) return `In ${m / 60} hour${m === 60 ? '' : 's'}`
  return `In ${m} minute${m === 1 ? '' : 's'}`
}

function localMidnight(day: string): number {
  const [y, mo, d] = day.split('-').map(Number)
  return y && mo && d ? new Date(y, mo - 1, d).getTime() : NaN
}
