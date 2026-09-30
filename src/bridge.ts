// Which pages the app trusts (src/WebShell.tsx). Only the Kinwall server's own origin stays in the
// app and gets the key, and only messages carrying this launch's nonce reach the native side: the
// nonce lives in the shim injected into the main frame alone, so other frames (a plugin's, on
// Android where every frame has window.ReactNativeWebView) can't send as the page.

/** Same scheme, host and port as the server: an http:// page on the same host doesn't count. */
export function sameOrigin(url: string, server: string): boolean {
  try { return new URL(url).origin === new URL(server).origin } catch { return false }
}

/** A bridge message, or null unless it carries `nonce` and the page (the top frame's URL) is the
 * server's own and not a plugin's (/plugins/). */
export function bridgeMessage(data: string, nonce: string, pageUrl: string, server: string): Record<string, unknown> | null {
  if (!sameOrigin(pageUrl, server) || new URL(pageUrl).pathname.startsWith('/plugins/')) return null
  let m: unknown
  try { m = JSON.parse(data) } catch { return null }
  if (!m || typeof m !== 'object' || (m as { nonce?: unknown }).nonce !== nonce) return null
  return m as Record<string, unknown>
}
