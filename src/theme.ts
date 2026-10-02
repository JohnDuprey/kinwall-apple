import * as SecureStore from 'expo-secure-store'
import * as SplashScreen from 'expo-splash-screen'
import { useMemo } from 'react'
import { StyleSheet, useColorScheme } from 'react-native'
import { type Appearance, parseAppearance } from './appearance'

// The native screens (address, sign-in, can't reach) in Kinwall's own colors, light and dark, the
// same tokens the web app's default scheme uses, so the frame matches what loads inside it.
// Eucalyptus (web/src/skins.ts); buttons carry white text on the light accent (6.3:1), dark ink on the dark one (8.3:1).
const LIGHT = { bg: '#EAF2EF', field: '#F9FCFB', text: '#13262A', dim: '#455F62', border: '#B6CDC4', accent: '#1F6B63', ink: '#FFFFFF', problem: '#B3261E' }
const DARK = { bg: '#0E1A1A', field: '#1A2D2C', text: '#E3EEEC', dim: '#9EB9B6', border: '#3E5D5B', accent: '#5CC2B3', ink: '#0E1A1A', problem: '#FF8A80' }
export type Palette = typeof LIGHT

const make = (c: Palette) => StyleSheet.create({
  root: { flex: 1, backgroundColor: c.bg },
  screen: { flex: 1, justifyContent: 'center', padding: 24, gap: 16, maxWidth: 520, width: '100%', alignSelf: 'center' },
  title: { fontSize: 32, fontWeight: '700', textAlign: 'center', color: c.text },
  muted: { color: c.dim, textAlign: 'center', fontSize: 16, lineHeight: 22 },
  footnote: { fontSize: 14, lineHeight: 20 },
  input: { padding: 14, borderRadius: 14, backgroundColor: c.field, borderWidth: 1.5, borderColor: c.border, color: c.text, fontSize: 17 },
  button: { backgroundColor: c.accent, padding: 14, borderRadius: 12, alignItems: 'center', minHeight: 50, justifyContent: 'center' },
  buttonText: { color: c.ink, fontSize: 17, fontWeight: '600' },
  // Disabled keeps readable text: the field's color with a border, not a faded accent.
  disabled: { backgroundColor: c.field, borderWidth: 1.5, borderColor: c.border },
  disabledText: { color: c.dim },
  secondary: { backgroundColor: c.field, borderWidth: 1.5, borderColor: c.border },
  secondaryText: { color: c.text },
  problem: { color: c.problem, fontSize: 15, textAlign: 'center' },
  link: { color: c.text, fontSize: 15, textAlign: 'center', padding: 8, textDecorationLine: 'underline' },
})

const STYLES = { light: make(LIGHT), dark: make(DARK) }

export function useUi() {
  const dark = useColorScheme() === 'dark'
  return useMemo(() => ({ ...(dark ? STYLES.dark : STYLES.light), c: dark ? DARK : LIGHT, dark }), [dark])
}

// The page's last look (src/appearance.ts), read synchronously so the first frame already has it.
// Kept beside the server address; cleared on sign-out, never saved from the demo.
const SAVED = 'appearance'
export function savedAppearance(): Appearance | null {
  try { return parseAppearance(SecureStore.getItem(SAVED)) } catch { return null }
}
export const saveAppearance = (a: Appearance) => SecureStore.setItemAsync(SAVED, JSON.stringify(a)).catch(() => {})
export const clearAppearance = () => SecureStore.deleteItemAsync(SAVED).catch(() => {})

/** The launch screen stays up (App.tsx) until what's under it is painted: a native screen, or the
 * page's first frame. Safe to call more than once. */
export const hideSplash = () => { SplashScreen.hideAsync().catch(() => {}) }
