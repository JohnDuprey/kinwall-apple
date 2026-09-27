import { useState } from 'react'
import { ActivityIndicator, Pressable, StyleSheet, Text, TextInput, View } from 'react-native'
import { isKinwall } from './api'
import { normalizeServer } from './server'

/** First launch: where is the family's Kinwall? Checks the address answers like a Kinwall server before handing it over. */
export function ServerEntry({ onConnect }: { onConnect: (url: string) => void }) {
  const [address, setAddress] = useState('')
  const [checking, setChecking] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)

  const connect = async () => {
    const url = normalizeServer(address)
    if (!url) { setProblem("That doesn't look like a web address."); return }
    setChecking(true); setProblem(null)
    const host = new URL(url).host
    try {
      if (await isKinwall(url)) onConnect(url)
      else setProblem(`${host} answered, but it isn't a Kinwall server.`)
    } catch {
      setProblem(`Couldn't reach ${host}. Check the address and your connection.`)
    } finally { setChecking(false) }
  }

  return (
    <View style={ui.screen}>
      <Text style={ui.title}>Welcome to Kinwall</Text>
      <Text style={ui.muted}>Enter your family's Kinwall address. For hosted Kinwall, your family name is enough.</Text>
      <TextInput style={ui.input} placeholder="ourfamily or kinwall.example.com" value={address} onChangeText={setAddress}
        autoCapitalize="none" autoCorrect={false} keyboardType="url" textContentType="URL" returnKeyType="go" onSubmitEditing={connect} autoFocus />
      {problem && <Text style={ui.problem}>{problem}</Text>}
      <Pressable style={[ui.button, (checking || !address.trim()) && ui.disabled]} onPress={connect} disabled={checking || !address.trim()}>
        {checking ? <ActivityIndicator color="#fff" /> : <Text style={ui.buttonText}>Connect</Text>}
      </Pressable>
      <Text style={[ui.muted, ui.footnote]}>You'll sign in on the next screen. An admin approves this device in Kinwall under Settings → Access.</Text>
    </View>
  )
}

export const ui = StyleSheet.create({
  screen: { flex: 1, justifyContent: 'center', padding: 24, gap: 16, maxWidth: 520, width: '100%', alignSelf: 'center' },
  title: { fontSize: 32, fontWeight: '700', textAlign: 'center' },
  muted: { color: '#6e6e73', textAlign: 'center', fontSize: 16 },
  footnote: { fontSize: 13 },
  input: { padding: 14, borderRadius: 14, backgroundColor: 'rgba(120,120,128,0.12)', fontSize: 17 },
  button: { backgroundColor: '#A5613F', padding: 14, borderRadius: 12, alignItems: 'center', minHeight: 50, justifyContent: 'center' },
  secondary: { backgroundColor: 'rgba(120,120,128,0.16)' },
  disabled: { opacity: 0.4 },
  buttonText: { color: '#fff', fontSize: 17, fontWeight: '600' },
  secondaryText: { color: '#A5613F' },
  problem: { color: '#d33', fontSize: 13, textAlign: 'center' },
  link: { color: '#A5613F', fontSize: 13, textAlign: 'center', padding: 8 },
})
