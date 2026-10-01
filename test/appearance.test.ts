// node --test test/ (npm test). The colors the app paints its frame in, from the page's last look.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { activityColors, frameColors, parseAppearance, widgetPalette } from '../src/appearance.ts'

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

test('activityColors: the family\'s background with readable text and accent; none without a look', () => {
  assert.deepEqual(activityColors(frameColors(parseAppearance({ mode: 'dark', dark: true, colors }), false)), { bg: '#0F1420', fg: '#E5F0EA', accent: '#44C28D' })
  assert.deepEqual(activityColors({ bg: '#FFFBF5', card: '#FFFFFF', dark: false }), { bg: '#FFFBF5', fg: '#14261D', accent: '#00774B' })
  assert.equal(activityColors(null), null)
})

test('widgetPalette: the family surfaces, light and dark as the family set them', () => {
  const auto = parseAppearance({ mode: 'auto', dark: false, colors })!
  assert.equal(widgetPalette(auto, false).bg, '#FFFBF5')
  assert.equal(widgetPalette(auto, true).bg, '#0F1420')
  assert.equal(widgetPalette(auto, true).fg, '#E5F0EA')
  // The family chose dark: the widget stays dark with the system light.
  const dark = parseAppearance({ mode: 'dark', dark: true, colors })!
  assert.deepEqual(widgetPalette(dark, false), widgetPalette(dark, true))
  assert.equal(widgetPalette(dark, false).card, '#1B2333')
  // Nothing saved yet: Kinwall's own, following the system.
  // Nothing saved yet: Kinwall's own, Sage (the web app's default scheme), following the system.
  assert.equal(widgetPalette(null, false).bg, '#E9F6EF')
  assert.equal(widgetPalette(null, true).bg, '#0D1D15')
})
