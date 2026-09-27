import * as SecureStore from 'expo-secure-store'

// The household's Kinwall address.
const KEY = 'serverURL'

export const loadServer = async () => (await SecureStore.getItemAsync(KEY)) ?? null
export const saveServer = (url: string) => SecureStore.setItemAsync(KEY, url)
export const clearServer = () => SecureStore.deleteItemAsync(KEY)

/** "ourfamily" → https://ourfamily.kinwall.family, "kinwall.local:8080" → http://kinwall.local:8080,
 * "http://192.168.1.20:8080" stays as typed. Null for anything that isn't a web address. */
export function normalizeServer(raw: string): string | null {
  let s = raw.trim()
  if (!s) return null
  if (!s.includes('.') && !s.includes(':') && !s.includes('/') && s !== 'localhost') s = `${s}.kinwall.family` // hosted family name
  if (!/^https?:\/\//i.test(s)) {
    // A home server by IP, localhost or a .local name rarely has https; everything else does.
    const host = s.split('/')[0]!.split(':')[0]!
    const local = host === 'localhost' || host.endsWith('.local') || /^[\d.]+$/.test(host)
    s = (local ? 'http://' : 'https://') + s
  }
  try {
    const u = new URL(s)
    if (!u.hostname) return null
    u.search = ''; u.hash = ''
    if (!u.pathname.endsWith('/')) u.pathname += '/'
    return u.toString()
  } catch { return null }
}
