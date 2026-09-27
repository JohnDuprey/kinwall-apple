/** @type {import('@bacons/apple-targets/app.plugin').Config} */
module.exports = {
  type: 'widget',
  name: 'KinwallWidgets',
  displayName: 'Kinwall',
  bundleIdentifier: '.widgets',
  deploymentTarget: '17.0',
  frameworks: ['SwiftUI', 'WidgetKit', 'AppIntents'],
  entitlements: { 'keychain-access-groups': ['$(AppIdentifierPrefix)family.kinwall.shared'] },
}
