import * as Linking from 'expo-linking'
import * as Notifications from 'expo-notifications'
import { useCallback, useEffect, useState } from 'react'
import { AppState } from 'react-native'
import * as SplashScreen from 'expo-splash-screen'
import { StatusBar } from 'expo-status-bar'
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context'
import type { Tokens } from './oauth'
import { DEMO_URL, enterDemo, leaveDemo } from './demo'
import { refreshReminders, scheduleBackgroundRefresh } from './reminders'
import { clearServer, loadServer, saveServer } from './server'
import { ServerEntry } from './ServerEntry'
import { type Session, freshTokens, loadSession, signOut } from './session'
import { syncWatch } from './sharedKey'
import { routeFor } from './links'
import { endAllActivities, endStaleActivities } from './liveActivities'
import { SignIn } from './SignIn'
import { WebShell } from './WebShell'
import { hideSplash, useUi } from './theme'
import KinwallNative from '../modules/kinwall-native'

// The launch screen stays up until the saved session is known and what's under it has painted
// (hideSplash), so a signed-in launch never shows the sign-in screen or the app's own colors.
SplashScreen.preventAutoHideAsync().catch(() => {})

/** The phone and tablet app: the household's own Kinwall web app, full screen, in a native frame
 * (docs/PLAN.md). First launch asks for the server, then signs in (OAuth in the system's auth
 * sheet, or a pairing code). */

export default function App() {
  const [server, setServer] = useState<string | null | undefined>() // undefined: still loading
  const [session, setSession] = useState<Session>(null)
  const [route, setRoute] = useState<string | null>(null) // a tab to show, from a widget link or a reminder
  const url = Linking.useURL()
  const ui = useUi()
  const tapped = Notifications.useLastNotificationResponse()

  // The demo is never saved, so a fresh launch clears anything it left for the widgets and reminders.
  useEffect(() => { leaveDemo(); loadServer().then(async (s) => { setSession(s ? await launchSession(s) : null); setServer(s) }) }, [])
  // The native screens (address, sign-in) are ready as soon as they're shown; the web view hides
  // the launch screen itself once the page has painted (src/WebShell.tsx).
  useEffect(() => { if (server === null || (server && !session)) hideSplash() }, [server, session])

  // Widget links: family.kinwall.app:/open?to=chores (or calendar, lists), plus &done=<chore id>
  // to tap that chore in the web app (it asks "Who did it?" or opens the checklist); and shared
  // recipe links (to=recipes/import&url=…), which open the web app's recipe import.
  useEffect(() => { if (url) { const r = routeFor(url); if (r) setRoute(r) } }, [url])
  // A tapped reminder opens its event.
  useEffect(() => {
    const r = tapped?.notification.request.content.data?.route
    if (typeof r === 'string') setRoute(r)
  }, [tapped])

  // Reminders are rescheduled each time the app opens or goes to the background.
  useEffect(() => {
    refreshReminders(); endStaleActivities()
    const sub = AppState.addEventListener('change', (s) => { if (s === 'background') scheduleBackgroundRefresh(); if (s === 'active') { refreshReminders(); endStaleActivities() } })
    const watch = KinwallNative?.addListener('watchStateChanged', () => { syncWatch() }) // e.g. the Watch app was just installed
    return () => { sub.remove(); watch?.remove() }
  }, [])

  // Leaving the demo is the same as changing server: back to the first screen (the demo was never
  // saved), with its sample widgets and reminders cleared (src/demo.ts).
  const changeServer = useCallback(async () => { endAllActivities(); if (session?.mode === 'demo') await leaveDemo(); else { await signOut(session); await clearServer() } setSession(null); setServer(null) }, [session])
  const signedOut = useCallback(async () => { if (session?.mode === 'demo') { await leaveDemo(); setSession(null); setServer(null); return } await signOut(session); setSession(null) }, [session])
  const tryDemo = useCallback(() => { setSession({ mode: 'demo' }); setServer(DEMO_URL); enterDemo() }, [])
  const onTokens = useCallback((tokens: Tokens) => setSession({ mode: 'oauth', tokens }), [])
  const routeApplied = useCallback(() => setRoute(null), [])

  return (
    <SafeAreaProvider>
      {server === undefined ? null
        : !server ? <SafeAreaView style={ui.root}><StatusBar style={ui.dark ? 'light' : 'dark'} /><ServerEntry onConnect={async (u) => { await leaveDemo(); await saveServer(u); setServer(u) }} onDemo={tryDemo} /></SafeAreaView>
        : !session ? <SafeAreaView style={ui.root}><StatusBar style={ui.dark ? 'light' : 'dark'} /><SignIn server={server} onSession={setSession} onChangeServer={changeServer} /></SafeAreaView>
        : <WebShell url={server} session={session} route={route} onRouteApplied={routeApplied} onTokens={onTokens} onSignedOut={signedOut} onChangeServer={changeServer} />}
    </SafeAreaProvider>
  )
}

/** The saved session, with OAuth keys refreshed first if they've lapsed (they last an hour): the
 * page would otherwise start with a dead key, get a 401 and flash its pairing screen before the
 * app caught up. Offline keeps the old key (freshTokens); a grant that's gone means sign in. */
async function launchSession(server: string): Promise<Session> {
  const s = await loadSession(server)
  if (s?.mode !== 'oauth') return s
  // A slow network doesn't hold the launch: past a few seconds, carry on with the old key (the
  // page's 401 comes back to WebShell, which refreshes and reloads).
  const tokens = await Promise.race([freshTokens(s.tokens), new Promise<Tokens>((r) => setTimeout(() => r(s.tokens), 4000))])
  return tokens ? { mode: 'oauth', tokens } : null
}
