import { useState } from 'react'
import { ActivityIndicator, Pressable, Text, TextInput, View } from 'react-native'
import { isKinwall } from './api'
import { normalizeServer } from './server'
import { useUi } from './theme'

/** First launch: where is the family's Kinwall? Checks the address answers like a Kinwall server before handing it over. */
export function ServerEntry({ onConnect, onDemo }: { onConnect: (url: string) => void; onDemo: () => void }) {
  const [address, setAddress] = useState('')
  const [checking, setChecking] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const ui = useUi()

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
      <TextInput style={ui.input} placeholder="ourfamily or kinwall.example.com" placeholderTextColor={ui.c.dim} value={address}
        onChangeText={(t) => { setAddress(t); setProblem(null) }} keyboardAppearance={ui.dark ? 'dark' : 'light'} selectionColor={ui.c.accent}
        autoCapitalize="none" autoCorrect={false} keyboardType="url" textContentType="URL" returnKeyType="go" onSubmitEditing={connect} autoFocus />
      {problem && <Text style={ui.problem}>{problem}</Text>}
      <Pressable style={[ui.button, !address.trim() && ui.disabled]} onPress={connect} disabled={checking || !address.trim()}>
        {checking ? <ActivityIndicator color={ui.c.ink} /> : <Text style={[ui.buttonText, !address.trim() && ui.disabledText]}>Connect</Text>}
      </Pressable>
      <Text style={[ui.muted, ui.footnote]}>You'll sign in on the next screen. An admin approves this device in Kinwall under Settings → Access.</Text>
      <Pressable onPress={onDemo} accessibilityRole="button" accessibilityHint="Opens Kinwall with a sample family. Nothing is saved.">
        <Text style={ui.link}>Try the demo</Text>
      </Pressable>
      <Text style={[ui.muted, ui.footnote]}>A sample family to look around in. Nothing is saved.</Text>
    </View>
  )
}
