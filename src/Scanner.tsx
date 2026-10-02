import { CameraView, useCameraPermissions } from 'expo-camera'
import { useEffect, useRef } from 'react'
import { Linking, Modal, Pressable, StyleSheet, Text, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { cleanBarcode } from './barcode'
import { useUi } from './theme'

// The barcodes on books (ISBN) and groceries. iOS reports a UPC-A as an EAN-13 with a leading 0.
const TYPES = ['ean13', 'ean8', 'upc_a', 'upc_e'] as const

/** Full-screen barcode scanner (the page's Scan buttons: Add a book, and shopping lists; web/src/native.ts): the first barcode it
 * reads, or null when closed. Asks for the camera the first time it opens. */
export function Scanner({ onDone }: { onDone: (code: string | null) => void }) {
  const ui = useUi()
  const [permission, request] = useCameraPermissions()
  const done = useRef(false)
  const finish = (code: string | null) => { if (done.current) return; done.current = true; onDone(code) }

  useEffect(() => { if (permission && !permission.granted && permission.canAskAgain) request() }, [permission, request])

  return (
    <Modal animationType="slide" presentationStyle="fullScreen" onRequestClose={() => finish(null)}>
      {permission?.granted ? (
        <View style={styles.root}>
          <CameraView
            style={StyleSheet.absoluteFill}
            facing="back"
            barcodeScannerSettings={{ barcodeTypes: [...TYPES] }}
            onBarcodeScanned={({ data }) => { const code = cleanBarcode(data); if (code) finish(code) }}
          />
          <SafeAreaView style={styles.overlay}>
            <Text style={styles.hint} accessibilityRole="header">Point at the barcode</Text>
            <View style={styles.frame} accessible={false} />
            <Pressable style={styles.close} onPress={() => finish(null)} accessibilityRole="button">
              <Text style={styles.closeText}>Cancel</Text>
            </Pressable>
          </SafeAreaView>
        </View>
      ) : (
        <View style={ui.root}><View style={ui.screen}>
          <Text style={ui.title}>Scan a barcode</Text>
          <Text style={ui.muted}>
            {permission && !permission.canAskAgain
              ? 'Kinwall needs the camera to scan. Turn it on in Settings, then try again.'
              : 'Kinwall uses the camera to read barcodes on books and groceries.'}
          </Text>
          {permission && !permission.canAskAgain
            ? <Pressable style={ui.button} onPress={() => Linking.openSettings()}><Text style={ui.buttonText}>Open Settings</Text></Pressable>
            : <Pressable style={ui.button} onPress={() => request()}><Text style={ui.buttonText}>Allow camera</Text></Pressable>}
          <Pressable onPress={() => finish(null)}><Text style={ui.link}>Cancel</Text></Pressable>
        </View></View>
      )}
    </Modal>
  )
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#000' },
  overlay: { flex: 1, alignItems: 'center', justifyContent: 'space-between', padding: 24 },
  hint: { color: '#fff', fontSize: 20, fontWeight: '700', textAlign: 'center', marginTop: 24, textShadowColor: '#000', textShadowRadius: 6 },
  frame: { width: '85%', maxWidth: 420, aspectRatio: 2, borderWidth: 3, borderColor: '#fff', borderRadius: 16 },
  close: { backgroundColor: 'rgba(0,0,0,0.6)', borderWidth: 1.5, borderColor: '#fff', borderRadius: 12, minHeight: 50, minWidth: 160, paddingHorizontal: 24, alignItems: 'center', justifyContent: 'center', marginBottom: 16 },
  closeText: { color: '#fff', fontSize: 17, fontWeight: '600' },
})
