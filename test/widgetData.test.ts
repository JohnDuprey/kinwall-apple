// node --test test/ (npm test). The Android widgets' rows and taps.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { type FamilyList, choreRows, choreTap, pickGroceries, takeNowText } from '../src/widgetData.ts'
import type { ChoreDay } from '../src/reminderPlans.ts'

const list = (id: string, name: string, kind: FamilyList['kind'], archived = false): FamilyList => ({ id, name, kind, archived, openCount: 0 })

test('pickGroceries: Groceries, else the first shopping list, else the first list', () => {
  assert.equal(pickGroceries([list('a', 'To-dos', 'todo'), list('b', 'Costco', 'shopping'), list('c', ' groceries ', 'shopping')])?.id, 'c')
  assert.equal(pickGroceries([list('a', 'To-dos', 'todo'), list('b', 'Costco', 'shopping')])?.id, 'b')
  assert.equal(pickGroceries([list('x', 'Groceries', 'shopping', true), list('a', 'To-dos', 'todo')])?.id, 'a')
  assert.equal(pickGroceries([]), null)
})

const chore = (id: string, memberId: string | null, extra: Partial<ChoreDay> = {}): ChoreDay => ({ id, title: id, memberId, completed: false, ...extra })

test('choreRows: one person with Anyone chores, or everyone; ones left first', () => {
  const all = [chore('done', 'm3', { completed: true }), chore('mine', 'm3'), chore('leo', 'm4'), chore('anyone', null)]
  assert.deepEqual(choreRows(all, 'm3').map((c) => c.id), ['mine', 'anyone', 'done'])
  assert.deepEqual(choreRows(all, null).map((c) => c.id), ['mine', 'leo', 'anyone', 'done'])
})

test('choreTap: ticks where it can, opens the app where it needs more', () => {
  assert.deepEqual(choreTap(chore('a', 'm3'), null), { tick: true, memberId: null })
  assert.deepEqual(choreTap(chore('a', null), 'm3'), { tick: true, memberId: 'm3' }) // Anyone, credited to the widget's person
  assert.deepEqual(choreTap(chore('a', null), null), { tick: false, open: 'chores&done=a' }) // Who did it?
  assert.deepEqual(choreTap(chore('a', 'm3', { checklist: { total: 3, done: 1 } }), 'm3'), { tick: false, open: 'chores&done=a' })
  assert.deepEqual(choreTap(chore('a', 'm3', { checklist: { total: 3, done: 3 } }), 'm3'), { tick: true, memberId: null })
  assert.deepEqual(choreTap(chore('a', 'm3', { completed: true }), 'm3'), { tick: false, open: 'chores' })
})

test('takeNowText: a count, never a name', () => {
  assert.equal(takeNowText(0), 'Nothing due now')
  assert.equal(takeNowText(2), '2 due now')
})
