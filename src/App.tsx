import * as Linking from 'expo-linking'
import * as Notifications from 'expo-notifications'
import { useCallback, useEffect, useState } from 'react'
import { AppState } from 'react-native'
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context'
import type { Tokens } from './oauth'
import { refreshReminders, scheduleBackgroundRefresh } from './reminders'
import { clearServer, loadServer, saveServer } from './server'
import { ServerEntry } from './ServerEntry'
import { type Session, loadSession, signOut } from './session'
import { syncWatch } from './sharedKey'
import { SignIn } from './SignIn'
import { WebShell } from './WebShell'
import KinwallNative from '../modules/kinwall-native'

/** The phone and tablet app: the household's own Kinwall web app, full screen, in a native frame
 * (docs/PLAN.md). First launch asks for the server, then signs in (OAuth in the system's auth
 * sheet, or a pairing code). */
export default function App() {
  const [server, setServer] = useState<string | null | undefined>() // undefined: still loading
  const [session, setSession] = useState<Session>(null)
  const [route, setRoute] = useState<string | null>(null) // a tab to show, from a widget link or a reminder
  const url = Linking.useURL()
  const tapped = Notifications.useLastNotificationResponse()

  useEffect(() => { loadServer().then(async (s) => { setSession(s ? await loadSession(s) : null); setServer(s) }) }, [])

  // Widget links: family.kinwall.app:/open?to=chores (or calendar, lists), plus &done=<chore id>
  // to tap that chore in the web app (it asks "Who did it?" or opens the checklist).
  useEffect(() => { if (url) { const r = routeFor(url); if (r) setRoute(r) } }, [url])
  // A tapped reminder opens its event.
  useEffect(() => {
    const r = tapped?.notification.request.content.data?.route
    if (typeof r === 'string') setRoute(r)
  }, [tapped])

  // Reminders are rescheduled each time the app opens or goes to the background.
  useEffect(() => {
    refreshReminders()
    const sub = AppState.addEventListener('change', (s) => { if (s === 'background') scheduleBackgroundRefresh(); if (s === 'active') refreshReminders() })
    const watch = KinwallNative?.addListener('watchStateChanged', () => { syncWatch() }) // e.g. the Watch app was just installed
    return () => { sub.remove(); watch?.remove() }
  }, [])

  const changeServer = useCallback(async () => { await signOut(session); await clearServer(); setSession(null); setServer(null) }, [session])
  const signedOut = useCallback(async () => { await signOut(session); setSession(null) }, [session])
  const onTokens = useCallback((tokens: Tokens) => setSession({ mode: 'oauth', tokens }), [])
  const routeApplied = useCallback(() => setRoute(null), [])

  return (
    <SafeAreaProvider>
      {server === undefined ? null
        : !server ? <SafeAreaView style={{ flex: 1 }}><ServerEntry onConnect={async (u) => { await saveServer(u); setServer(u) }} /></SafeAreaView>
        : !session ? <SafeAreaView style={{ flex: 1 }}><SignIn server={server} onSession={setSession} onChangeServer={changeServer} /></SafeAreaView>
        : <WebShell url={server} session={session} route={route} onRouteApplied={routeApplied} onTokens={onTokens} onSignedOut={signedOut} onChangeServer={changeServer} />}
    </SafeAreaProvider>
  )
}

/** family.kinwall.app:/open?to=chores&done=abc → "chores?done=abc"; anything else → null. */
export function routeFor(link: string): string | null {
  const m = /^family\.kinwall\.app:\/*open\?(.*)$/.exec(link)
  if (!m) return null
  const q = new URLSearchParams(m[1])
  const to = q.get('to')
  if (!to || !['calendar', 'chores', 'lists'].includes(to)) return null
  const done = q.get('done')
  // The id lands in page script, so only plain id characters pass.
  return to === 'chores' && done && /^[A-Za-z0-9_-]+$/.test(done) ? `chores?done=${done}` : to
}
