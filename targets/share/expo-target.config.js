/** @type {import('@bacons/apple-targets/app.plugin').Config} */
// The share sheet's "Kinwall": imports a shared recipe link on the spot (ShareViewController.swift),
// signed in with what the app keeps in the shared Keychain group.
module.exports = {
  type: 'share',
  name: 'KinwallShare',
  displayName: 'Kinwall',
  bundleIdentifier: '.share',
  deploymentTarget: '17.0',
  frameworks: ['UIKit', 'UniformTypeIdentifiers'],
  entitlements: { 'keychain-access-groups': ['$(AppIdentifierPrefix)family.kinwall.shared'] },
}
