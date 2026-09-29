import { type EventSubscription, requireOptionalNativeModule } from 'expo-modules-core'

type KinwallNative = {
  keychainGet(service: string, shared: boolean): Promise<string | null>
  keychainSet(service: string, shared: boolean, value: string | null): Promise<void>
  reloadWidgets(): void
  watchAppInstalled(): boolean
  updateWatch(context: Record<string, unknown>): void
  /** Live Activities (ios/LiveActivities.swift): payload is the web app's JSON for that kind. */
  activitySet(kind: string, payload: string, colors: { bg: string; fg: string; accent: string } | null): Promise<void>
  /** No kind: every one (sign-out). */
  activityEnd(kind: string | null): Promise<void>
  activityEndStale(): Promise<void>
  /** Live Activities allowed in iPhone Settings. */
  activitiesEnabled(): boolean
  /** iOS: a family.kinwall.app:/open link from Siri or a Control (native/ios/OpenIntents.swift), once. */
  takeLink?(): string | null
  addListener(event: 'watchStateChanged', listener: () => void): EventSubscription
  /** iOS: takeLink() has one. */
  addListener(event: 'link', listener: () => void): EventSubscription
  /** With push (a paid team): a token for the server, PUT /api/live-activities/tokens. */
  addListener(event: 'activityToken', listener: (t: ActivityToken) => void): EventSubscription
}
export type ActivityToken = { kind: 'start' | 'update'; token: string; activity?: string; endsAt?: string }

/** Null on Android: widgets there render from JavaScript (src/widgets.tsx), and there's no Watch link. */
export default requireOptionalNativeModule<KinwallNative>('KinwallNative')
