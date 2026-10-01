import * as SecureStore from 'expo-secure-store'
import * as SplashScreen from 'expo-splash-screen'
import { useMemo } from 'react'
import { StyleSheet, useColorScheme } from 'react-native'
import { type Appearance, parseAppearance } from './appearance'

// The native screens (address, sign-in, can't reach) in Kinwall's own colors, light and dark, the
// same tokens the web app's default scheme uses, so the frame matches what loads inside it.
// Sage (web/src/skins.ts); buttons carry white text on the light accent (5.6:1), dark ink on the dark one.
const LIGHT = { bg: '#E9F6EF', field: '#F9FEFB', text: '#14261D', dim: '#446353', border: '#B8D3C4', accent: '#00774B', ink: '#FFFFFF', problem: '#B3261E' }
const DARK = { bg: '#0D1D15', field: '#193025', text: '#E5F0EA', dim: '#A0BEAE', border: '#3D5E4D', accent: '#44C28D', ink: '#0D1D15', problem: '#FF8A80' }
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
