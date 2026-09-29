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
