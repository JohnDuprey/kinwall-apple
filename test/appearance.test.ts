// node --test test/ (npm test). The colors the app paints its frame in, from the page's last look.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { frameColors, parseAppearance } from '../src/appearance.ts'

const colors = { light: { bg: '#FFFBF5', card: '#FFFFFF' }, dark: { bg: '#0F1420', card: '#1B2333' } }

test('parseAppearance: takes the page message or the saved copy', () => {
  const a = parseAppearance({ type: 'appearance', mode: 'dark', dark: true, colors })
  assert.deepEqual(a, { mode: 'dark', dark: true, colors })
  assert.deepEqual(parseAppearance(JSON.stringify(a)), a)
})

test('parseAppearance: rejects anything that is not plain hex colors', () => {
  assert.equal(parseAppearance(null), null)
  assert.equal(parseAppearance('not json'), null)
  assert.equal(parseAppearance({ mode: 'dark', dark: true }), null)
  assert.equal(parseAppearance({ mode: 'dark', dark: true, colors: { ...colors, dark: { bg: 'red', card: '#000000' } } }), null)
  assert.equal(parseAppearance({ mode: 'dark', dark: true, colors: { ...colors, dark: { bg: '#000000"); alert(1', card: '#000000' } } }), null)
  assert.equal(parseAppearance({ mode: 'sepia', dark: true, colors }), null)
})

test('frameColors: nothing saved means the app\'s own colors', () => {
  assert.equal(frameColors(null, true), null)
})

test('frameColors: light, dark and scheduled use the page\'s last look', () => {
  assert.deepEqual(frameColors({ mode: 'dark', dark: true, colors }, false), { dark: true, ...colors.dark })
  assert.deepEqual(frameColors({ mode: 'light', dark: false, colors }, true), { dark: false, ...colors.light })
  assert.deepEqual(frameColors({ mode: 'scheduled', dark: true, colors }, false), { dark: true, ...colors.dark })
})

test('frameColors: auto follows the system now, not when it was saved', () => {
  const a = { mode: 'auto' as const, dark: false, colors }
  assert.deepEqual(frameColors(a, true), { dark: true, ...colors.dark })
  assert.deepEqual(frameColors(a, false), { dark: false, ...colors.light })
})
