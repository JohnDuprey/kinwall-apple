import KinwallNative from '../modules/kinwall-native'
import { api } from './api'
import { type Contact, type List, type Recipe, type SpotlightItem, spotlightItems } from './spotlightItems'
import { widgetConnection } from './sharedKey'

// Spotlight on iPhone and iPad: the family's recipes, lists and contacts (names and a short line,
// src/spotlightItems.ts), fetched with the widgets' key whenever the app opens or comes back (at
// most every 10 minutes), and cleared on sign-out. A tapped result opens its page. No-op on Android.

const EVERY = 10 * 60_000
let last = 0

export async function syncSpotlight(force = false): Promise<void> {
  if (!KinwallNative?.spotlightSet || (!force && Date.now() - last < EVERY)) return
  const c = await widgetConnection()
  if (!c) return
  last = Date.now()
  const get = <T>(path: string) => api<T[]>(c.baseURL, c.key, 'GET', path).catch(() => null)
  // Features a family turned off answer 404 (or aren't there): those just have no items.
  const [recipes, lists, contacts] = await Promise.all([get<Recipe>('api/recipes'), get<List>('api/lists'), get<Contact>('api/contacts')])
  if (!recipes && !lists && !contacts) { last = 0; return } // offline: try again next time
  await KinwallNative.spotlightSet(spotlightItems({ recipes: recipes ?? [], lists: lists ?? [], contacts: contacts ?? [] })).catch(() => {})
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

