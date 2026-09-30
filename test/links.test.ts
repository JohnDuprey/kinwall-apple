// node --test test/ (npm test). The app's family.kinwall.app:/open links: widgets, Live Activities, shares.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { groceriesRoute, routeFor } from '../src/links.ts'

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

test('routeFor: Siri and the Controls open shopping mode at a store, a list, the night screen', () => {
  assert.equal(routeFor('family.kinwall.app:/open?to=lists/l1/shop&store=Shaw%27s%20%26%20Co'), 'lists/l1/shop?store=Shaw\'s%20%26%20Co')
  assert.equal(routeFor('family.kinwall.app:/open?to=lists&list=l1'), 'lists?list=l1')
  assert.equal(routeFor('family.kinwall.app:/open?to=lists&list=x%27)'), 'lists', 'only plain ids reach page script')
  assert.equal(routeFor('family.kinwall.app:/open?to=night'), 'night')
})

test('routeFor: Spotlight opens a recipe, a list or a contact', () => {
  assert.equal(routeFor('family.kinwall.app:/open?to=meals&recipe=r-1'), 'meals?recipe=r-1')
  assert.equal(routeFor('family.kinwall.app:/open?to=contacts&contact=c_2'), 'contacts?contact=c_2')
  assert.equal(routeFor('family.kinwall.app:/open?to=contacts'), 'contacts')
  assert.equal(routeFor('family.kinwall.app:/open?to=meals&recipe=%3Cx%3E'), 'meals')
})

test('routeFor: the check-in widget opens that person\'s check-in', () => {
  assert.equal(routeFor('family.kinwall.app:/open?to=checkin&member=m3'), 'calendar?checkin=m3')
  assert.equal(routeFor('family.kinwall.app:/open?to=checkin&member=%3C'), 'calendar')
})

test('Android shortcuts and tiles: Groceries, found by the app', () => {
  assert.equal(routeFor('family.kinwall.app:/open?to=groceries'), 'groceries')
  assert.equal(routeFor('family.kinwall.app:/open?to=groceries/shop'), 'groceries/shop')
  assert.equal(groceriesRoute('groceries', 'l1'), 'lists?list=l1')
  assert.equal(groceriesRoute('groceries/shop', 'l1'), 'lists/l1/shop')
  assert.equal(groceriesRoute('groceries', null), 'lists')
  assert.equal(groceriesRoute('groceries/shop', "x')"), 'lists')
})
