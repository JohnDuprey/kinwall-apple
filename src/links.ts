// The app's own links (family.kinwall.app:/open?…) from widgets, Live Activities, reminders and
// shares, as the web app's route. No React Native imports, so test/links.test.ts runs it under node.

/** family.kinwall.app:/open?to=chores&done=abc → "chores?done=abc"; a shared recipe page,
 * ?to=recipes/import&url=<page> (from an Android share) →
 * "recipes/import?url=<page>"; a trip's Live Activity, ?to=lists/<id>/shop → shopping mode
 * (Siri adds &store=); Siri and the Controls, ?to=lists&list=<id> and ?to=night; Spotlight,
 * ?to=meals&recipe=<id> and ?to=contacts&contact=<id>; anything else → null. */
export function routeFor(link: string): string | null {
  const m = /^family\.kinwall\.app:\/*open\?(.*)$/.exec(link)
  if (!m) return null
  const q = new URLSearchParams(m[1])
  const to = q.get('to')?.replace(/^\//, '')
  if (to === 'recipes/import') {
    const page = q.get('url')
    return page && /^https?:\/\/[^\s]+$/i.test(page) && page.length <= 2000 ? `recipes/import?url=${encodeURIComponent(page)}` : null
  }
  // Ids land in page script, so only plain id characters pass.
  const id = (v: string | null) => (v && /^[A-Za-z0-9_-]+$/.test(v) ? v : null)
  // Shopping mode; Siri's "Start shopping at <store>" adds the store (the web app picks it up once
  // it reads ?store=; until then it asks, as it always has).
  if (to && /^lists\/[A-Za-z0-9_-]+\/shop$/.test(to)) {
    const store = q.get('store')?.trim()
    return store && store.length <= 100 ? `${to}?store=${encodeURIComponent(store)}` : to
  }
  if (to === 'night') return 'night' // the night screen (WebShell sends the 🌙 button's event)
  if (to === 'lists') { const l = id(q.get('list')); return l ? `lists?list=${l}` : 'lists' }
  // Spotlight: a recipe or a contact (src/spotlight.ts).
  if (to === 'meals') { const r = id(q.get('recipe')); return r ? `meals?recipe=${r}` : 'meals' }
  if (to === 'contacts') { const c = id(q.get('contact')); return c ? `contacts?contact=${c}` : 'contacts' }
  if (!to || !['calendar', 'chores'].includes(to)) return null
  const done = id(q.get('done'))
  return to === 'chores' && done ? `chores?done=${done}` : to
}
