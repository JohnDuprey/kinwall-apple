import { useMemo } from 'react'
import { StyleSheet, useColorScheme } from 'react-native'

// The native screens (address, sign-in, can't reach) in Kinwall's own colors, light and dark, the
// same tokens the web app's default scheme uses, so the frame matches what loads inside it.
const LIGHT = { bg: '#FFFBF5', field: '#FFFFFF', text: '#3A2E27', dim: '#6B5D52', border: '#E8D8C6', accent: '#A5613F', ink: '#FFFFFF', problem: '#B3261E' }
const DARK = { bg: '#1C1712', field: '#2A221B', text: '#F3EAE0', dim: '#C4B5A7', border: '#4A3C30', accent: '#FF9E7A', ink: '#2A1A12', problem: '#FF8A80' }
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
