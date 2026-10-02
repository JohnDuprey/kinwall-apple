// The page's look, as the web app reports it (web/src/native.ts tellAppAppearance in the kinwall
// repo): saved so the next launch paints the frame, the splash's hand-off and the page's first
// frame in the family's colors instead of flashing the app's own. No React Native imports here, so
// test/appearance.test.ts runs it under plain node.

export type Surface = { bg: string; card: string }
export type Appearance = { mode: 'light' | 'dark' | 'auto' | 'scheduled'; dark: boolean; colors: { light: Surface; dark: Surface } }

const HEX = /^#[0-9a-f]{6}$/i
const MODES = ['light', 'dark', 'auto', 'scheduled']
const surface = (v: unknown): Surface | null => {
  const s = v as Partial<Surface> | null
  return s && typeof s.bg === 'string' && HEX.test(s.bg) && typeof s.card === 'string' && HEX.test(s.card) ? { bg: s.bg, card: s.card } : null
}

/** The page's message or the saved JSON; null for anything else (it comes from a web page and
 * ends up in injected script, so only plain hex colors pass). */
export function parseAppearance(v: unknown): Appearance | null {
  let a: Partial<Appearance> | null
  try { a = typeof v === 'string' ? JSON.parse(v) : v } catch { return null }
  if (!a || typeof a !== 'object' || !MODES.includes(a.mode as string) || typeof a.dark !== 'boolean') return null
  const light = surface(a.colors?.light), dark = surface(a.colors?.dark)
  return light && dark ? { mode: a.mode!, dark: a.dark, colors: { light, dark } } : null
}

/** The frame's colors now: 'auto' follows the system's current appearance; the other modes use
 * whatever the page last showed ('scheduled' included: its hours are the page's to work out). */
export function frameColors(a: Appearance | null, systemDark: boolean): (Surface & { dark: boolean }) | null {
  if (!a) return null
  const dark = a.mode === 'auto' ? systemDark : a.dark
  return { dark, ...(dark ? a.colors.dark : a.colors.light) }
}

/** The colors sent with a Live Activity: the frame's background with Kinwall's text and accent for
 * light or dark; null for Kinwall's own. Only the accent is used now (the cooking alarm's tint on
 * iOS, Android's countdown notification color): the activity itself draws on the system's
 * background with Kinwall's blue-green as an accent (targets/widgets/LiveActivities.swift). */
export function activityColors(frame: (Surface & { dark: boolean }) | null): { bg: string; fg: string; accent: string } | null {
  if (!frame) return null
  return frame.dark ? { bg: frame.bg, fg: '#E3EEEC', accent: '#5CC2B3' } : { bg: frame.bg, fg: '#13262A', accent: '#1F6B63' }
}

/** The Android widgets' colors (src/widgets.tsx): the family's surfaces with Kinwall's text and
 * accent, light or dark as the frame would be; Kinwall's own (src/theme.ts) before the page has
 * sent any. `systemDark`: the representation Android asks for (its dark theme on or off). */
type Hex = `#${string}`
export type WidgetPalette = { bg: Hex; card: Hex; fg: Hex; dim: Hex; accent: Hex }
const LIGHT: WidgetPalette = { bg: '#EAF2EF', card: '#F9FCFB', fg: '#13262A', dim: '#455F62', accent: '#1F6B63' }
const DARK: WidgetPalette = { bg: '#0E1A1A', card: '#1A2D2C', fg: '#E3EEEC', dim: '#9EB9B6', accent: '#5CC2B3' }
export function widgetPalette(a: Appearance | null, systemDark: boolean): WidgetPalette {
  const f = frameColors(a, systemDark)
  const base = (f ? f.dark : systemDark) ? DARK : LIGHT
  return f ? { ...base, bg: f.bg as Hex, card: f.card as Hex } : base // parseAppearance only passes #rrggbb
}
