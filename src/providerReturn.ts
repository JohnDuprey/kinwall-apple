// Connecting Google or Microsoft (a calendar, Google Photos) starts in the web view, which gets the
// sign-in's cookie, but the provider's page opens in the in-app browser (WebShell openOutside),
// which has cookies of its own. So the server's callback, reached there without the cookie, offers
// this link instead (kinwall server/src/routes/oauth.ts handBack):
//   family.kinwall.app:/provider-return?kind=google|microsoft&state=…&code=…
// and the app loads that callback in its web view, where the cookie is. Only ever on the app's own
// server: a link can come from anywhere, so nothing in it picks the host. A code is no use without
// the cookie (only this web view has it) and the server's PKCE verifier. A path apart from the
// sign-in's /oauth (src/oauth.ts): Android's auth session matches links by prefix.
// No React Native imports, so test/providerReturn.test.ts runs it under node.

const PROVIDER_RETURN = /^family\.kinwall\.app:\/?provider-return\?(.*)$/

/** A provider-return link, good or bad (App.tsx drops a bad one rather than reading it as another kind of link). */
export const isProviderReturn = (link: string) => PROVIDER_RETURN.test(link)

/** The link's callback on `server` (the app's own Kinwall address), or null unless the link is a
 * well-formed provider return: kind google or microsoft, a plain state and code of bounded length. */
export function providerReturnUrl(link: string, server: string): string | null {
  const m = PROVIDER_RETURN.exec(link)
  if (!m) return null
  const q = new URLSearchParams(m[1])
  const kind = q.get('kind'), state = q.get('state'), code = q.get('code')
  if (kind !== 'google' && kind !== 'microsoft') return null
  if (!state || !/^[A-Za-z0-9._-]{1,200}$/.test(state)) return null // a UUID, or "<family>.<kind>.<UUID>" on a shared host
  if (!code || !/^[A-Za-z0-9._~/+=-]{1,4096}$/.test(code)) return null // Google's "4/0A…", Microsoft's long dotted ones
  let base: URL
  try { base = new URL(server.endsWith('/') ? server : `${server}/`) } catch { return null }
  if (base.protocol !== 'https:' && base.protocol !== 'http:') return null
  const url = new URL(`api/oauth/${kind}/callback`, base)
  url.search = new URLSearchParams({ code, state }).toString()
  return url.toString()
}
