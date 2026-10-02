// node --test test/ (npm test). A Google/Microsoft sign-in handed back from the in-app browser
// (family.kinwall.app:/provider-return, kinwall server/src/routes/oauth.ts) → the callback on the
// app's own server, to load in the web view where the sign-in's cookie is.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { isProviderReturn, providerReturnUrl } from '../src/providerReturn.ts'

const SERVER = 'https://smiths.kinwall.family/'
const link = (q: Record<string, string>) => `family.kinwall.app:/provider-return?${new URLSearchParams(q)}`

test('providerReturnUrl: the callback on the app\'s own server, with the code and state', () => {
  const state = 'smiths.google.0b6861e3-1505-4952-9411-d2f3ab1a335d'
  const code = '4/0AeaYSHb+x_y-z.~='
  const u = new URL(providerReturnUrl(link({ kind: 'google', state, code }), SERVER)!)
  assert.equal(u.origin + u.pathname, 'https://smiths.kinwall.family/api/oauth/google/callback')
  assert.deepEqual(Object.fromEntries(u.searchParams), { code, state })
  assert.equal(new URL(providerReturnUrl(link({ kind: 'microsoft', state: 'abc', code: '0.AXo-1' }), SERVER)!).pathname, '/api/oauth/microsoft/callback')
})

test('providerReturnUrl: a server under a path keeps it; one without a trailing slash too', () => {
  assert.equal(providerReturnUrl(link({ kind: 'google', state: 's', code: 'c' }), 'https://home.example/kinwall/'), 'https://home.example/kinwall/api/oauth/google/callback?code=c&state=s')
  assert.equal(providerReturnUrl(link({ kind: 'google', state: 's', code: 'c' }), 'http://192.168.1.20:8080'), 'http://192.168.1.20:8080/api/oauth/google/callback?code=c&state=s')
})

test('providerReturnUrl: never a host from the link, only the app\'s own server', () => {
  for (const extra of [{ host: 'evil.example' }, { server: 'https://evil.example/' }, { redirect: 'https://evil.example/' }]) {
    const u = providerReturnUrl(link({ kind: 'google', state: 's', code: 'c', ...extra }), SERVER)!
    assert.ok(u.startsWith('https://smiths.kinwall.family/api/oauth/google/callback?'), u)
    assert.ok(!u.includes('evil'), u)
  }
  assert.equal(providerReturnUrl('family.kinwall.app://evil.example/provider-return?kind=google&state=s&code=c', SERVER), null, 'no authority in the link')
})

test('providerReturnUrl: anything off is refused', () => {
  const ok = { kind: 'google', state: 's', code: 'c' }
  assert.equal(providerReturnUrl(link({ ...ok, kind: 'yahoo' }), SERVER), null)
  assert.equal(providerReturnUrl(link({ ...ok, kind: '../../api/keys' }), SERVER), null)
  assert.equal(providerReturnUrl(link({ kind: 'google', code: 'c' }), SERVER), null, 'no state')
  assert.equal(providerReturnUrl(link({ kind: 'google', state: 's' }), SERVER), null, 'no code')
  assert.equal(providerReturnUrl(link({ ...ok, state: 's"><x' }), SERVER), null)
  assert.equal(providerReturnUrl(link({ ...ok, state: 'x'.repeat(201) }), SERVER), null)
  assert.equal(providerReturnUrl(link({ ...ok, code: 'a b' }), SERVER), null)
  assert.equal(providerReturnUrl(link({ ...ok, code: 'x'.repeat(4097) }), SERVER), null)
  assert.equal(providerReturnUrl(link(ok).replace('provider-return', 'oauth'), SERVER), null, 'the app\'s own sign-in link is not this')
  assert.equal(providerReturnUrl(link(ok).replace('provider-return', 'open'), SERVER), null)
  assert.equal(providerReturnUrl('https://smiths.kinwall.family/provider-return?kind=google&state=s&code=c', SERVER), null)
  assert.equal(providerReturnUrl(link(ok), 'not a url'), null)
  assert.equal(providerReturnUrl(link(ok), 'javascript:alert(1)//'), null)
})

test('isProviderReturn: only the provider-return link', () => {
  assert.ok(isProviderReturn(link({ kind: 'google', state: 's', code: 'c' })))
  assert.ok(isProviderReturn('family.kinwall.app:/provider-return?kind=yahoo'), 'even a bad one is ours to drop')
  assert.ok(!isProviderReturn('family.kinwall.app:/open?to=calendar'))
  assert.ok(!isProviderReturn('family.kinwall.app:/oauth?code=c&state=s'))
})
