import KinwallNative from '../modules/kinwall-native'

// iOS: the widgets are the WidgetKit extension in targets/widgets; just tell it to refetch.
export const reloadWidgets = () => KinwallNative?.reloadWidgets()
export const registerWidgets = () => {}
