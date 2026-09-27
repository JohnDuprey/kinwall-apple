import Constants from 'expo-constants'
import { activateKeepAwakeAsync, deactivateKeepAwake } from 'expo-keep-awake'
import { StatusBar } from 'expo-status-bar'
import { useEffect, useRef, useState } from 'react'
import { AppState, BackHandler, Dimensions, Linking, Platform, Pressable, StyleSheet, Text, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { WebView, type WebViewMessageEvent } from 'react-native-webview'
import type { Tokens } from './oauth'
import { refreshReminders, requestPermission } from './reminders'
import { useUi } from './theme'
import { type Session, freshTokens, needsRefresh } from './session'
import { ensureWidgetKey, syncWatch, widgetConnection } from './sharedKey'
import { reloadWidgets } from './widgets'

const isTablet = Platform.OS === 'ios' ? Platform.isPad : Math.min(Dimensions.get('screen').width, Dimensions.get('screen').height) >= 600
const VERSION = Constants.expoConfig?.version ?? '0'

/** Read by the web app to adapt (hide the Add to Home Screen card and web push, which don't
 * apply inside the app). Keep in sync with web/src/native.ts in the kinwall repo, which posts to
 * webkit.messageHandlers.kinwall: that's shimmed onto the WebView's own channel here. */
const bridge = (token: string | null) => `
window.kinwallNative = { platform: ${JSON.stringify(Platform.OS)}, version: ${JSON.stringify(VERSION)} };
${token ? `try { localStorage.setItem('kinwall.apiKey', ${JSON.stringify(token)}) } catch (e) {}` : ''}
(function () {
  var post = function (m) { window.ReactNativeWebView.postMessage(JSON.stringify(m)) };
  var kinwall = { postMessage: post };
  // Our handler goes on WebKit's messageHandlers object, which loses added properties when its
  // wrapper is garbage-collected: holding references keeps it (window.webkit can't be replaced).
  try {
    var ns = window.webkit;
    if (ns && ns.messageHandlers) {
      Object.defineProperty(ns.messageHandlers, 'kinwall', { value: kinwall });
      window.__kinwallHold = [ns, ns.messageHandlers];
    } else window.webkit = { messageHandlers: { kinwall: kinwall } }; // Android
  } catch (e) {}
  var last = '';
  var theme = function () {
    var m = document.querySelector('meta[name="theme-color"]');
    if (m && m.content && m.content !== last) { last = m.content; post({ type: 'theme', color: m.content }) }
  };
  new MutationObserver(theme).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['content'] });
})();
true;`

type Props = {
  url: string
  session: NonNullable<Session>
  route: string | null
  onRouteApplied: () => void
  onTokens: (t: Tokens) => void
  onSignedOut: () => void
  onChangeServer: () => void
}

/** The Kinwall web app, full screen. Tells the page it's inside the app, keeps other sites in
 * the browser, follows the page's theme color, and hands the paired key to the widgets, Watch and Siri. */
export function WebShell({ url, session, route, onRouteApplied, onTokens, onSignedOut, onChangeServer }: Props) {
  const web = useRef<WebView>(null)
  const [theme, setTheme] = useState('#ffffff')
  const [failed, setFailed] = useState<string | null>(null)
  const ui = useUi()
  const [loading, setLoading] = useState(true)
  const [startsPairing, setStartsPairing] = useState<boolean | null>(null)
  const pending = useRef<string | null>(null)
  const canGoBack = useRef(false)
  const host = new URL(url).host
  const token = session.mode === 'oauth' ? session.tokens.accessToken : null

  // A wall tablet stays awake; a phone sleeps as usual.
  useEffect(() => {
    if (!isTablet) return
    activateKeepAwakeAsync('wall').catch(() => {})
    return () => { deactivateKeepAwake('wall').catch(() => {}) }
  }, [])

  // Chose "Pair with a code": open the page on its pairing code (web/src/App.tsx reads ?start=pair).
  useEffect(() => { widgetConnection().then((c) => setStartsPairing(session.mode === 'paired' && !c)) }, [session.mode])

  // OAuth keys last an hour: refresh ahead of time while the app is open, and on every return.
  useEffect(() => {
    if (session.mode !== 'oauth') return
    let timer: ReturnType<typeof setInterval> | undefined
    const tick = async () => {
      if (AppState.currentState !== 'active' || !needsRefresh(session.tokens)) return
      const next = await freshTokens(session.tokens)
      if (!next) { onSignedOut(); return }
      onTokens(next)
      web.current?.injectJavaScript(`localStorage.setItem('kinwall.apiKey', ${JSON.stringify(next.accessToken)}); true;`)
    }
    timer = setInterval(tick, 60_000)
    const sub = AppState.addEventListener('change', (s) => { if (s === 'active') tick() })
    return () => { clearInterval(timer); sub.remove() }
  }, [session, onTokens, onSignedOut])

  // A tab to show (a widget link or a tapped reminder): once the page is up.
  useEffect(() => {
    if (!route) return
    if (loading) { pending.current = route } else { go(route) }
    onRouteApplied()
  }, [route, loading, onRouteApplied])

  // Android: back goes back in the web app's history, else leaves.
  useEffect(() => {
    if (Platform.OS !== 'android') return
    const sub = BackHandler.addEventListener('hardwareBackPress', () => { if (!canGoBack.current) return false; web.current?.goBack(); return true })
    return () => sub.remove()
  }, [])

  const go = (to: string) => web.current?.injectJavaScript(`location.hash = ${JSON.stringify('#/' + to)}; true;`)
  const isKinwall = (u: string) => { try { return new URL(u).host === host } catch { return false } }

  /** Once the page is signed in (its key is in localStorage 'kinwall.apiKey'), make sure the widgets have their own key. */
  const syncKey = () => web.current?.injectJavaScript(`window.ReactNativeWebView.postMessage(JSON.stringify({ type: 'key', key: localStorage.getItem('kinwall.apiKey') })); true;`)

  const onMessage = async (e: WebViewMessageEvent) => {
    let m: { type?: string; reason?: string; color?: string; key?: string | null }
    try { m = JSON.parse(e.nativeEvent.data) } catch { return }
    switch (m.type) {
      case 'theme': if (m.color) setTheme(m.color); break
      case 'signedIn': syncKey(); break
      case 'signedOut': // web/src/native.ts: the page cleared its key
        // `rejected` (a 401): after a sleep the OAuth key may simply have lapsed, so refresh and carry on.
        if (m.reason === 'rejected' && session.mode === 'oauth') {
          const next = await freshTokens(session.tokens)
          if (next) { onTokens(next); web.current?.reload(); return }
        }
        onSignedOut(); break
      case 'key':
        if (!m.key) return
        await ensureWidgetKey(url, m.key)
        reloadWidgets()
        await requestPermission() // first time signed in: ask, then schedule
        await refreshReminders()
        await syncWatch()
        break
    }
  }

  const dark = isDark(theme)
  const view = failed ? (
    <View style={ui.root}><View style={ui.screen}>
      <Text style={ui.title}>Can't reach Kinwall</Text>
      <Text style={ui.muted}>{failed}</Text>
      <Pressable style={ui.button} onPress={() => { setFailed(null); web.current?.reload() }}><Text style={ui.buttonText}>Try again</Text></Pressable>
      <Pressable onPress={onChangeServer}><Text style={ui.link}>Change server</Text></Pressable>
    </View></View>
  ) : startsPairing === null ? null : (
    <WebView
      ref={web}
      style={styles.web}
      source={{ uri: startsPairing ? `${url}?start=pair` : url }}
      applicationNameForUserAgent={`KinwallApp/${VERSION}`}
      injectedJavaScriptBeforeContentLoaded={bridge(token)}
      onMessage={onMessage}
      onLoadStart={() => setLoading(true)}
      onLoadEnd={() => { setLoading(false); syncKey(); if (pending.current) { go(pending.current); pending.current = null } }}
      onNavigationStateChange={(s) => { canGoBack.current = s.canGoBack }}
      onError={(e) => setFailed(e.nativeEvent.description)}
      // Other sites (docs, maps, sign-in pages) open in the browser; Kinwall stays here.
      onShouldStartLoadWithRequest={(r) => {
        if (isKinwall(r.url) || r.url.startsWith('about:') || r.url.startsWith('blob:')) return true
        if (r.isTopFrame !== false) Linking.openURL(r.url).catch(() => {})
        return false
      }}
      onOpenWindow={(e) => { const u = e.nativeEvent.targetUrl; if (isKinwall(u)) web.current?.injectJavaScript(`location.href = ${JSON.stringify(u)}; true;`); else Linking.openURL(u).catch(() => {}) }}
      onFileDownload={(e) => { Linking.openURL(e.nativeEvent.downloadUrl).catch(() => {}) }} // the photo zip, a saved drawing: the browser saves it
      contentInsetAdjustmentBehavior="never" // the page lays itself out with env(safe-area-inset-*)
      bounces={false}
      allowsInlineMediaPlayback
      allowsBackForwardNavigationGestures={false}
      allowsLinkPreview={false}
      setSupportMultipleWindows
      webviewDebuggingEnabled={__DEV__}
      domStorageEnabled
    />
  )

  // iOS: the page uses the full screen and drops its status-bar gap in the app (data-native).
  // Android: the page starts under the status bar; the insets are painted in the page's color.
  return Platform.OS === 'ios' ? (
    <View style={[styles.root, { backgroundColor: theme }]}>
      <StatusBar hidden style={dark ? 'light' : 'dark'} />
      {view}
    </View>
  ) : (
    <SafeAreaView style={[styles.root, { backgroundColor: theme }]}>
      <StatusBar style={dark ? 'light' : 'dark'} />
      {view}
    </SafeAreaView>
  )
}

function isDark(hex: string): boolean {
  const v = /^#([0-9a-f]{6})$/i.exec(hex)
  if (!v) return false
  const n = parseInt(v[1]!, 16)
  return (0.2126 * ((n >> 16) & 255) + 0.7152 * ((n >> 8) & 255) + 0.0722 * (n & 255)) / 255 < 0.5
}

const styles = StyleSheet.create({ root: { flex: 1 }, web: { flex: 1, backgroundColor: 'transparent' } })
