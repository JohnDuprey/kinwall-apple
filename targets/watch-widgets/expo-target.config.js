/** @type {import('@bacons/apple-targets/app.plugin').Config} */
module.exports = {
  type: 'watch-widget',
  name: 'KinwallWatchWidgets',
  displayName: 'Kinwall',
  bundleIdentifier: '.watchkitapp.complications',
  deploymentTarget: '10.0',
  frameworks: ['SwiftUI', 'WidgetKit'],
  entitlements: { 'keychain-access-groups': ['$(AppIdentifierPrefix)family.kinwall.shared'] },
}
