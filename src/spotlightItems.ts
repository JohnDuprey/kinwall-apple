// What Spotlight shows for the family (src/spotlight.ts indexes it): recipes, lists and contacts,
// names and a short line only. Never health data, notes, phone numbers or addresses. Each item's
// id is the app link it opens (src/links.ts routeFor). No React Native imports, so
// test/spotlight.test.ts runs it under node.

export type SpotlightItem = { id: string; title: string; description: string; kind: 'recipe' | 'list' | 'contact' }

export type Recipe = { id: string; name: string; description?: string | null; totalMinutes?: number | null }
export type List = { id: string; name: string; emoji?: string | null; kind: string; archived: boolean; openCount: number }
export type Contact = { id: string; name: string; kind?: string | null; relationship?: string | null; organization?: string | null }

const ID = /^[A-Za-z0-9_-]+$/
const short = (s: string, max = 120) => { const one = s.replace(/\s+/g, ' ').trim(); return one.length > max ? `${one.slice(0, max - 1).trimEnd()}…` : one }
const line = (...parts: (string | null | undefined | false)[]) => short(parts.filter(Boolean).join(' · '))
const LIST_KIND: Record<string, string> = { shopping: 'Shopping list', todo: 'To-do list', reusable: 'Reusable list' }

export function spotlightItems(d: { recipes: Recipe[]; lists: List[]; contacts: Contact[] }): SpotlightItem[] {
  const link = (to: string, key: string, id: string) => `family.kinwall.app:/open?to=${to}&${key}=${id}`
  return [
    ...d.recipes.filter((r) => ID.test(r.id)).map((r) => ({ id: link('meals', 'recipe', r.id), title: r.name, kind: 'recipe' as const, description: line('Recipe', r.totalMinutes ? `${r.totalMinutes} min` : null, r.description) })),
    ...d.lists.filter((l) => !l.archived && ID.test(l.id)).map((l) => ({ id: link('lists', 'list', l.id), title: l.emoji ? `${l.emoji} ${l.name}` : l.name, kind: 'list' as const, description: line(LIST_KIND[l.kind] ?? 'List', `${l.openCount} left`) })),
    ...d.contacts.filter((c) => ID.test(c.id)).map((c) => ({ id: link('contacts', 'contact', c.id), title: c.name, kind: 'contact' as const, description: line('Contact', c.relationship || c.organization) })),
  ]
}
