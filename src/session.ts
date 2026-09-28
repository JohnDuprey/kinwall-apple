import * as SecureStore from 'expo-secure-store'
import { type Tokens, clearTokens, loadTokens, refresh, revoke, saveTokens, OAuthError } from './oauth'
import { clearReminders } from './reminders'
import { revokeWidgetKey, shareKey, watchSignOut } from './sharedKey'
import { reloadWidgets } from './widgets'

// How this device is signed in to the household: OAuth tokens (kept fresh here), or a paired
// key the web app holds itself. Null means "show the sign-in screen".
export type Session = { mode: 'oauth'; tokens: Tokens } | { mode: 'paired' } | { mode: 'demo' } | null

const PAIRED = 'signedInWithPairing'

export async function loadSession(server: string): Promise<Session> {
  const tokens = await loadTokens()
  if (tokens?.baseURL === server) return { mode: 'oauth', tokens }
  if ((await SecureStore.getItemAsync(PAIRED)) === '1') return { mode: 'paired' }
  return null
}

export async function signedIn(tokens: Tokens): Promise<Session> {
  await saveTokens(tokens)
  await SecureStore.deleteItemAsync(PAIRED)
  return { mode: 'oauth', tokens }
}

export async function choosePairing(): Promise<Session> {
  await SecureStore.setItemAsync(PAIRED, '1')
  return { mode: 'paired' }
}

/** Refresh a little early so a request never goes out with a token about to lapse. */
export const needsRefresh = (t: Tokens) => t.expiresAt - Date.now() < 5 * 60_000

let refreshing: Promise<Tokens | null> | null = null
/** Tokens good for at least five minutes, refreshing if needed. Null when the grant is gone
 * (revoked, or the refresh token expired): the caller signs out. */
export function freshTokens(t: Tokens): Promise<Tokens | null> {
  if (!needsRefresh(t)) return Promise.resolve(t)
  if (refreshing) return refreshing // one refresh at a time: refresh tokens rotate
  refreshing = (async () => {
    // The share extension may have refreshed them since (refresh tokens rotate): start from the saved ones.
    const saved = await loadTokens()
    const cur = saved?.baseURL === t.baseURL ? saved : t
    if (!needsRefresh(cur)) return cur
    const next = await refresh(cur)
    await saveTokens(next)
    return next
  })()
    .catch((e: unknown) => (e instanceof OAuthError && e.needsSignIn ? null : t)) // offline: keep the old one and try again later
    .finally(() => { refreshing = null })
  return refreshing
}

/** Back to the sign-in screen, ending the OAuth grant on the server. */
export async function signOut(session: Session): Promise<void> {
  if (session?.mode === 'oauth') await revoke(session.tokens)
  await clearTokens()
  await shareKey(null)
  await revokeWidgetKey()
  await clearReminders()
  await watchSignOut()
  await SecureStore.deleteItemAsync(PAIRED)
  reloadWidgets()
}
