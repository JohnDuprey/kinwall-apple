// node --test test/ (npm test). The app's family.kinwall.app:/open links: widgets, Live Activities, shares.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { routeFor } from '../src/links.ts'

test('routeFor: tabs, a chore to tick, a recipe to import', () => {
  assert.equal(routeFor('family.kinwall.app:/open?to=calendar'), 'calendar')
  assert.equal(routeFor('family.kinwall.app:/open?to=chores&done=c1'), 'chores?done=c1')
  assert.equal(routeFor('family.kinwall.app:/open?to=recipes/import&url=https%3A%2F%2Fexample.org%2Ftacos'), 'recipes/import?url=https%3A%2F%2Fexample.org%2Ftacos')
  assert.equal(routeFor('family.kinwall.app:/open?to=settings'), null)
  assert.equal(routeFor('https://example.org'), null)
})

test('routeFor: a shopping trip\'s Live Activity opens its list in shopping mode', () => {
  assert.equal(routeFor('family.kinwall.app:/open?to=lists/l-1_a/shop'), 'lists/l-1_a/shop')
  assert.equal(routeFor('family.kinwall.app:/open?to=lists/x\'%3Balert(1)/shop'), null, 'only plain id characters reach page script')
})
