import { type EventSubscription, requireOptionalNativeModule } from 'expo-modules-core'

type KinwallNative = {
  keychainGet(service: string, shared: boolean): Promise<string | null>
  keychainSet(service: string, shared: boolean, value: string | null): Promise<void>
  reloadWidgets(): void
  watchAppInstalled(): boolean
  updateWatch(context: Record<string, unknown>): void
  addListener(event: 'watchStateChanged', listener: () => void): EventSubscription
}

/** Null on Android: widgets there render from JavaScript (src/widgets.tsx), and there's no Watch link. */
export default requireOptionalNativeModule<KinwallNative>('KinwallNative')
