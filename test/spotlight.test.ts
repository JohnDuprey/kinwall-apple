// node --test test/ (npm test). What Spotlight gets from the family's recipes, lists and contacts.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spotlightItems } from '../src/spotlightItems.ts'
import { routeFor } from '../src/links.ts'

test('spotlightItems: names and a short line, each opening its page', () => {
  const items = spotlightItems({
    recipes: [{ id: 'r1', name: 'Lemon chicken', description: 'Bright and quick.\nServes 4, with rice on the side and a very long tail that keeps going and going past what Spotlight shows', totalMinutes: 35 }],
    lists: [{ id: 'l1', name: 'Groceries', emoji: '🛒', kind: 'shopping', archived: false, openCount: 12 }, { id: 'l2', name: 'Old', emoji: null, kind: 'todo', archived: true, openCount: 0 }],
    contacts: [{ id: 'c1', name: 'Dr. Rivera', kind: 'person', relationship: null, organization: 'Maple Pediatrics', notes: 'allergy notes', phones: [{ value: '555' }] }],
  })
  assert.deepEqual(items.map((i) => [i.id, i.title, i.kind]), [
    ['family.kinwall.app:/open?to=meals&recipe=r1', 'Lemon chicken', 'recipe'],
    ['family.kinwall.app:/open?to=lists&list=l1', '🛒 Groceries', 'list'],
    ['family.kinwall.app:/open?to=contacts&contact=c1', 'Dr. Rivera', 'contact'],
  ])
  assert.equal(items[0]!.description.length <= 120, true)
  assert.match(items[0]!.description, /^Recipe · 35 min · Bright and quick\./)
  assert.equal(items[1]!.description, 'Shopping list · 12 left')
  assert.equal(items[2]!.description, 'Contact · Maple Pediatrics', 'no notes, phones or anything else')
  for (const i of items) assert.ok(routeFor(i.id), 'every item opens a page')
})

test('spotlightItems: ids that could reach page script are skipped', () => {
  assert.equal(spotlightItems({ recipes: [{ id: 'x"<', name: 'Bad' }], lists: [], contacts: [] }).length, 0)
})

test('spotlightItems: nothing of a kind the family turned off; a missing switch is on', () => {
  const d = {
    recipes: [{ id: 'r1', name: 'Lemon chicken' }],
    lists: [{ id: 'l1', name: 'Groceries', kind: 'shopping', archived: false, openCount: 1 }],
    contacts: [{ id: 'c1', name: 'Dr. Rivera' }],
  }
  assert.deepEqual(spotlightItems(d, { meals: false, contacts: false }).map((i) => i.kind), ['list'])
  assert.deepEqual(spotlightItems(d, { lists: false, chores: false }).map((i) => i.kind), ['recipe', 'contact'])
  assert.equal(spotlightItems(d, {}).length, 3, 'an older server sends no switches')
})
