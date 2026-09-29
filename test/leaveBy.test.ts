// node --test test/ (npm test). Android: which leave-by / prep-by countdowns get an alarm, and when.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { firstWarning, leaveByAlarms } from '../src/leaveBy.ts'

const MIN = 60_000
const NOW = Date.parse('2026-09-29T15:00:00Z')
const iso = (m: number) => new Date(NOW + m * MIN).toISOString()
const me = { id: 'sam', transitionReminders: { on: true, minutes: [10, 30], repeat: null, leaveBy: true } }
const ev = (id: string, startMin: number, extra: Record<string, unknown> = {}) =>
  ({ id, title: id, start: iso(startMin), allDay: false, memberIds: [] as string[], leaveAt: iso(startMin - 20), ...extra })

test('firstWarning: the earliest of the minutes and the repeats, within 1 to 120', () => {
  assert.equal(firstWarning({ on: true, minutes: [10, 30] }), 30)
  assert.equal(firstWarning({ on: true, minutes: [5], repeat: { every: 15, within: 45 } }), 45)
  assert.equal(firstWarning({ on: true, minutes: [200, 0] }), undefined)
  assert.equal(firstWarning({ on: false, minutes: [10] }), undefined)
  assert.equal(firstWarning(undefined), undefined)
})

test('leaveByAlarms: warn at the first warning before the leave-by time, end at the start', () => {
  const [a, ...rest] = leaveByAlarms([ev('soccer', 120)], me, NOW)
  assert.equal(rest.length, 0)
  assert.deepEqual(a, {
    activity: `leaveBy:soccer@${iso(120)}`, eventId: 'soccer', title: 'soccer', prep: false,
    warnAt: NOW + 70 * MIN, at: NOW + 100 * MIN, endsAt: NOW + 120 * MIN,
  })
})

test('leaveByAlarms: stays a few minutes past the time when the event starts right after', () => {
  const [a] = leaveByAlarms([ev('bus', 60, { leaveAt: iso(59) })], me, NOW)
  assert.equal(a!.endsAt, NOW + 64 * MIN) // GRACE_MIN after the leave-by time
})

test('leaveByAlarms: only this person\'s timed events with a lead time, within the horizon', () => {
  const list = [
    ev('mine', 90, { memberIds: ['sam'] }),
    ev('theirs', 90, { memberIds: ['maya'] }),
    ev('allDay', 90, { allDay: true }),
    ev('noLead', 90, { leaveAt: null }),
    ev('over', -5), // started already
    ev('far', 26 * 60), // warns past 24 h
    ev('now', 25), // due now: its warning time has passed but it hasn't started
  ]
  assert.deepEqual(leaveByAlarms(list, me, NOW).map((a) => a.eventId), ['now', 'mine'])
})

test('leaveByAlarms: prep for the cook only; leave-by only when turned on', () => {
  const dinner = ev('dinner', 120, { leaveAt: null, prepAt: iso(60), cookId: 'maya', memberIds: ['sam'] })
  assert.deepEqual(leaveByAlarms([dinner], me, NOW), [])
  const mine = leaveByAlarms([{ ...dinner, cookId: 'sam' }], me, NOW)
  assert.equal(mine[0]!.prep, true)
  assert.equal(mine[0]!.warnAt, NOW + 30 * MIN)
  const noLeave = { ...me, transitionReminders: { ...me.transitionReminders, leaveBy: false } }
  assert.deepEqual(leaveByAlarms([ev('soccer', 120)], noLeave, NOW), [])
  assert.equal(leaveByAlarms([{ ...dinner, cookId: 'sam' }], noLeave, NOW).length, 1) // prep still counts
})

test('leaveByAlarms: off, or no warnings, schedules nothing; a repeat keeps its own id; capped', () => {
  assert.deepEqual(leaveByAlarms([ev('soccer', 120)], { id: 'sam', transitionReminders: { on: false, minutes: [10] } }, NOW), [])
  const weekly = [ev('lesson', 60), { ...ev('lesson', 120), leaveAt: iso(100) }]
  assert.deepEqual(leaveByAlarms(weekly, me, NOW).map((a) => a.activity), [`leaveBy:lesson@${iso(60)}`, `leaveBy:lesson@${iso(120)}`])
  const many = Array.from({ length: 40 }, (_, i) => ev(`e${i}`, 60 + i * 10))
  assert.equal(leaveByAlarms(many, me, NOW).length, 20)
  assert.deepEqual(leaveByAlarms([{ ...ev('bad', 60), start: 'nope' }], me, NOW), [])
})
