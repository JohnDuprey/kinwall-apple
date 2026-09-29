import * as Notifications from 'expo-notifications'
import * as SecureStore from 'expo-secure-store'
import { Alert, Platform } from 'react-native'
import KinwallNative from '../modules/kinwall-native'
import { CHANNEL, requestPermission } from './reminders'
import { reloadWidgets } from './widgets'
import { clearSpotlight, showDemoInSpotlight } from './spotlight'

/** The demo family (a static copy of the web app with sample data): no sign-in, nothing saved.
 * A debug build can point it at a local copy with EXPO_PUBLIC_DEMO_URL (the kinwall repo's
 * `npm run build:demo`, served locally) to try web changes that aren't live yet; a release build
 * always uses the real one. */
export const DEMO_URL = (__DEV__ && process.env.EXPO_PUBLIC_DEMO_URL) || 'https://demo.kinwall.family'

// While the demo is open, the iOS widgets and Spotlight show the demo family's built-in sample data and two
// sample reminders arrive, so a visitor (or an App Store reviewer) sees both with no server. The
// flag is a Keychain item in the widgets' shared group (KinwallKit's SharedKeychain.demoStore);
// the widgets ignore it whenever a real family's key is there.
const FLAG = 'family.kinwall.demo'
/** Only these; real reminders are "rem:" (src/reminders.ts) and never touch them. */
const PREFIX = 'demo:'
const TIP = 'demoTipShown'
const SAMPLES = [
  { id: 'soccer', seconds: 20, title: 'Soccer Practice', body: 'In 15 minutes · Park field', route: 'calendar' },
  { id: 'toys', seconds: 60, title: 'Time for Leo to tidy the toys', body: '🧸 Tap to tick it off in Chores', route: 'chores' },
]

export async function enterDemo(): Promise<void> {
  await KinwallNative?.keychainSet(FLAG, true, JSON.stringify({ baseURL: DEMO_URL, key: 'demo' })).catch(() => {})
  reloadWidgets()
  await showDemoInSpotlight()
  await requestPermission()
  const { granted } = await Notifications.getPermissionsAsync()
  for (const s of SAMPLES) {
    await Notifications.scheduleNotificationAsync({
      identifier: PREFIX + s.id,
      content: { title: s.title, body: s.body, sound: 'default', data: { route: s.route } },
      trigger: { type: Notifications.SchedulableTriggerInputTypes.TIME_INTERVAL, seconds: s.seconds, channelId: CHANNEL },
    }).catch(() => {})
  }
  // Once per device: how to see the widgets, and what's about to arrive.
  if (await SecureStore.getItemAsync(TIP).catch(() => '1')) return
  await SecureStore.setItemAsync(TIP, '1').catch(() => {})
  const widget = Platform.OS === 'ios' ? 'Add a Kinwall widget: touch and hold your Home Screen, tap Edit → Add Widget, then Kinwall.' : ''
  const reminder = granted ? 'A sample reminder arrives in a few seconds.' : ''
  const text = [widget, reminder].filter(Boolean).join(' ')
  if (text) Alert.alert('Welcome to the demo', text, [{ text: 'OK' }])
}

/** Leaving the demo, connecting a real family, or a fresh launch (the demo never survives one):
 * widgets back to their own state, and no demo reminder left pending or on screen. */
export async function leaveDemo(): Promise<void> {
  if (await KinwallNative?.keychainGet(FLAG, true).catch(() => null)) {
    await KinwallNative?.keychainSet(FLAG, true, null).catch(() => {})
    reloadWidgets()
    await clearSpotlight()
  }
  for (const s of SAMPLES) {
    await Notifications.cancelScheduledNotificationAsync(PREFIX + s.id).catch(() => {})
    await Notifications.dismissNotificationAsync(PREFIX + s.id).catch(() => {})
  }
}
