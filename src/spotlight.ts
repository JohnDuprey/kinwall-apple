import KinwallNative from '../modules/kinwall-native'
import { type Features, api } from './api'
import { type Contact, type List, type Recipe, type SpotlightItem, spotlightItems } from './spotlightItems'
import { widgetConnection } from './sharedKey'

// Spotlight on iPhone and iPad: the family's recipes, lists and contacts (names and a short line,
// src/spotlightItems.ts), fetched with the widgets' key whenever the app opens or comes back (at
// most every 10 minutes), and cleared on sign-out. A tapped result opens its page. Each sync
// replaces the whole index, so a kind the family turned off (Meals, Lists, Contacts: answered as
// usual by the server, not 404) is left out and what was indexed of it goes. No-op on Android.
//
// The same sync notices the family's feature switches changing and redraws the widgets on both
// platforms, so a Chores widget says "turned off" without waiting for its next refresh.

const EVERY = 10 * 60_000
let last = 0
let seen: string | null = null

export async function syncSpotlight(force = false): Promise<void> {
  if (!force && Date.now() - last < EVERY) return
  const c = await widgetConnection()
  if (!c) return
  last = Date.now()
  const settings = await api<{ features?: Features }>(c.baseURL, c.key, 'GET', 'api/settings').catch(() => null)
  if (!settings) { last = 0; return } // offline: try again next time
  const features = settings.features ?? {}
  const now = JSON.stringify(features)
  if (seen !== null && seen !== now) KinwallNative?.reloadWidgets()
  seen = now
  if (!KinwallNative?.spotlightSet) return
  const get = <T>(on: boolean, path: string) => (on ? api<T[]>(c.baseURL, c.key, 'GET', path).catch(() => null) : null)
  const [recipes, lists, contacts] = await Promise.all([get<Recipe>(features.meals !== false, 'api/recipes'), get<List>(features.lists !== false, 'api/lists'), get<Contact>(features.contacts !== false, 'api/contacts')])
  await KinwallNative.spotlightSet(spotlightItems({ recipes: recipes ?? [], lists: lists ?? [], contacts: contacts ?? [] }, features)).catch(() => {})
}

export async function clearSpotlight(): Promise<void> {
  last = 0
  await KinwallNative?.spotlightClear?.().catch(() => {})
}

/** The demo family (src/demo.ts): a few of its recipes, lists and contacts, so Spotlight shows it too. */
const DEMO: SpotlightItem[] = spotlightItems({
  recipes: [{ id: 'demo-chicken', name: 'Lemon chicken with rice and broccoli', description: 'A complete chicken dinner with rice and roasted vegetables.' }, { id: 'demo-parfaits', name: 'Berry yogurt parfaits', description: 'Layered yogurt, berries, and crunchy granola.' }],
  lists: [{ id: 'l1', name: 'Groceries', emoji: '🛒', kind: 'shopping', archived: false, openCount: 12 }],
  contacts: [{ id: 'contact-grandparent', name: 'Grandma Rosa', relationship: 'Grandparent' }, { id: 'contact-school', name: 'Maple Grove School', relationship: 'School office' }],
})
export const showDemoInSpotlight = () => KinwallNative?.spotlightSet?.(DEMO).catch(() => {})

