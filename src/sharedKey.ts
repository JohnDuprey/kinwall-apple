import * as SecureStore from 'expo-secure-store'
import { Platform } from 'react-native'
import KinwallNative from '../modules/kinwall-native'
import { type Connection, createDeviceKey, revokeOwnKey } from './api'

// The widgets' and the Watch's own everyday-access keys (docs/WIDGETS-AND-WATCH.md): minted once
// per server with whatever key the app is signed in with, revoked on sign-out. Never the app's
// rotating sign-in itself.
//
// iOS: kept by the native module exactly where KinwallKit's KeychainConnectionStore looks
// (service, account "household", the shared group for the widgets' key), so the widgets, Watch
// and Siri read it. Android: SecureStore; the widget there renders in JavaScript.
type Store = { service: string; shared: boolean }
const WIDGETS: Store = { service: 'family.kinwall.widgets', shared: true }
const WATCH: Store = { service: 'family.kinwall.watch', shared: false }
const secure = (s: Store) => ({ keychainService: s.service, keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK })

async function load(s: Store): Promise<Connection | null> {
  const v = await (KinwallNative ? KinwallNative.keychainGet(s.service, s.shared) : SecureStore.getItemAsync('household', secure(s))).catch(() => null)
  return v ? (JSON.parse(v) as Connection) : null
}
const save = (s: Store, c: Connection | null) =>
  KinwallNative ? KinwallNative.keychainSet(s.service, s.shared, c && JSON.stringify(c))
    : c ? SecureStore.setItemAsync('household', JSON.stringify(c), secure(s)) : SecureStore.deleteItemAsync('household', secure(s))

export const widgetConnection = () => load(WIDGETS)

/** Once the page is signed in, make sure the widgets have their key for this server. */
export async function ensureWidgetKey(baseURL: string, key: string): Promise<void> {
  if ((await load(WIDGETS))?.baseURL === baseURL) return
  const device = Platform.OS === 'ios' ? (Platform.isPad ? 'iPad' : 'iPhone') : 'Android'
  const minted = await createDeviceKey(baseURL, key, `Widgets on ${device}`).catch(() => null)
  if (minted) await save(WIDGETS, { baseURL, key: minted.key })
}

export async function revokeWidgetKey(): Promise<void> {
  const saved = await load(WIDGETS)
  if (saved) await revokeOwnKey(saved).catch(() => {})
  await save(WIDGETS, null).catch(() => {})
}

/** iOS: give the Watch its key (minted with the widgets' key, once per server) as application context. */
export async function syncWatch(): Promise<void> {
  if (!KinwallNative?.watchAppInstalled()) return
  const widgets = await load(WIDGETS)
  if (!widgets) return
  let watch = await load(WATCH)
  if (watch?.baseURL !== widgets.baseURL) {
    const minted = await createDeviceKey(widgets.baseURL, widgets.key, 'Apple Watch').catch(() => null)
    if (!minted) return
    watch = { baseURL: widgets.baseURL, key: minted.key }
    await save(WATCH, watch)
  }
  try { KinwallNative.updateWatch({ server: watch.baseURL, key: watch.key }) } catch {}
}

export async function watchSignOut(): Promise<void> {
  const watch = await load(WATCH)
  if (watch) await revokeOwnKey(watch).catch(() => {})
  await save(WATCH, null).catch(() => {})
  try { KinwallNative?.updateWatch({ signedOut: true }) } catch {}
}
