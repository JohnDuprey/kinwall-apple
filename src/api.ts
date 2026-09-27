// The slice of Kinwall's REST API the shell and the Android widget need (KinwallKit stays the
// Swift side's client). One fetch per call; callers own caching.

export type Connection = { baseURL: string; key: string }

export class ApiError extends Error {
  constructor(public status: number, message: string) { super(message) }
}

export type EventInstance = {
  id: string; title: string
  /** ISO instant for timed events; YYYY-MM-DD for all-day ones. */
  start: string; allDay: boolean; location?: string | null
  /** Minutes before start (or before leaveAt when remindBeforeLeave) to remind. */
  reminders?: number[] | null; leaveAt?: string | null; remindBeforeLeave?: boolean
}
export type BoardEvent = { id: string; title: string; start: string; end: string; allDay: boolean; color?: string | null; leaveAt?: string | null; date: string }
export type Board = {
  today: string
  events: BoardEvent[]
  chores: { memberId: string | null; name: string | null; avatar: string | null; remaining: number; total: number }[]
}

export async function api<T>(baseURL: string, key: string | null, method: string, path: string, body?: unknown): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json' }
  if (key) headers.Authorization = `Bearer ${key}`
  if (body !== undefined) headers['Content-Type'] = 'application/json'
  const res = await fetch(new URL(path, baseURL).toString(), { method, headers, body: body === undefined ? undefined : JSON.stringify(body) })
  if (!res.ok) {
    const e = (await res.json().catch(() => null)) as { error?: string } | null
    throw new ApiError(res.status, e?.error ?? `${res.status} ${res.statusText}`)
  }
  return (await res.json()) as T
}

/** Does this address answer like a Kinwall server? */
export async function isKinwall(baseURL: string): Promise<boolean> {
  const ctl = new AbortController()
  const t = setTimeout(() => ctl.abort(), 10_000)
  try {
    const res = await fetch(new URL('api/health', baseURL).toString(), { headers: { Accept: 'application/json' }, signal: ctl.signal })
    return res.status === 200
  } finally { clearTimeout(t) }
}

export const events = (c: Connection, from: Date, to: Date) =>
  api<EventInstance[]>(c.baseURL, c.key, 'GET', `api/events?from=${encodeURIComponent(from.toISOString())}&to=${encodeURIComponent(to.toISOString())}`)
export const board = (c: Connection, days = 1) => api<Board>(c.baseURL, c.key, 'GET', `api/board?days=${days}`)
/** An everyday-access key for widgets or the watch; the plaintext comes back once. */
export const createDeviceKey = (baseURL: string, key: string, name: string) =>
  api<{ id: string; key: string }>(baseURL, key, 'POST', 'api/device-keys', { name })
export const revokeOwnKey = (c: Connection) => api<{ ok: boolean }>(c.baseURL, c.key, 'DELETE', 'api/device-keys/self')

/** Timed events today that haven't ended: the one under way, and the next one. */
export function nowAndNext(b: Board, now = new Date()): { now?: BoardEvent; next?: BoardEvent } {
  const today = b.events.filter((e) => e.date === b.today && !e.allDay)
  const t = now.getTime()
  const current = today.find((e) => Date.parse(e.start) <= t && t < Date.parse(e.end))
  const next = today.filter((e) => Date.parse(e.start) > t).sort((a, b) => Date.parse(a.start) - Date.parse(b.start))[0]
  return { now: current, next }
}
