// The app's own links (family.kinwall.app:/open?…) from widgets, Live Activities, reminders and
// shares, as the web app's route. No React Native imports, so test/links.test.ts runs it under node.

/** family.kinwall.app:/open?to=chores&done=abc → "chores?done=abc"; a shared recipe page,
 * ?to=recipes/import&url=<page> (from an Android share) →
 * "recipes/import?url=<page>"; a trip's Live Activity, ?to=lists/<id>/shop → shopping mode;
 * anything else → null. */
export function routeFor(link: string): string | null {
  const m = /^family\.kinwall\.app:\/*open\?(.*)$/.exec(link)
  if (!m) return null
  const q = new URLSearchParams(m[1])
  const to = q.get('to')?.replace(/^\//, '')
  if (to === 'recipes/import') {
    const page = q.get('url')
    return page && /^https?:\/\/[^\s]+$/i.test(page) && page.length <= 2000 ? `recipes/import?url=${encodeURIComponent(page)}` : null
  }
  // The id lands in page script, so only plain id characters pass.
  if (to && /^lists\/[A-Za-z0-9_-]+\/shop$/.test(to)) return to
  if (!to || !['calendar', 'chores', 'lists'].includes(to)) return null
  const done = q.get('done')
  // The id lands in page script, so only plain id characters pass.
  return to === 'chores' && done && /^[A-Za-z0-9_-]+$/.test(done) ? `chores?done=${done}` : to
}
