// iOS native targets, on top of @bacons/apple-targets (which turns targets/* into the widget,
// Watch, complication and share targets): links the KinwallKit Swift package to every target, and
// compiles native/ios (Siri App Intents) into the app itself, where AppShortcutsProvider has to live.
const { withXcodeProjectBeta } = require('@bacons/apple-targets/build/with-bacons-xcode')
const withTargets = require('@bacons/apple-targets/app.plugin')
const { PBXBuildFile, PBXFileReference, PBXNativeTarget, XCLocalSwiftPackageReference, XCSwiftPackageProductDependency } = require('@bacons/xcode')
const { AndroidConfig, withAndroidManifest, withAppDelegate, withDangerousMod, withEntitlementsPlist, withInfoPlist, withMainActivity, withXcodeProject } = require('expo/config-plugins')
const fs = require('fs')
const path = require('path')

// A project path with a space in it: the template's bundling phase runs an unquoted backtick
// path, and expo-constants' script phase expands $PODS_TARGET_SRCROOT unquoted inside `bash -c`.
const withSpacesInPath = (config) => {
  config = withXcodeProject(config, (config) => {
    const phases = config.modResults.hash.project.objects.PBXShellScriptBuildPhase
    for (const phase of Object.values(phases)) {
      if (typeof phase !== 'object' || !phase.shellScript) continue
      phase.shellScript = phase.shellScript.replace(/`(\\"\$NODE_BINARY\\" --print [^`]*)`/, '\\"$($1)\\"')
    }
    return config
  })
  return withDangerousMod(config, ['ios', (config) => {
    const podfile = path.join(config.modRequest.platformProjectRoot, 'Podfile')
    const fix = `
    installer.pods_project.targets.each do |t|
      t.shell_script_build_phases.each { |p| p.shell_script = p.shell_script.gsub('$PODS_TARGET_SRCROOT/../scripts/get-app-config-ios.sh', '\\"$PODS_TARGET_SRCROOT/../scripts/get-app-config-ios.sh\\"') }
    end
`
    fs.writeFileSync(podfile, fs.readFileSync(podfile, 'utf8').replace('post_install do |installer|\n', `post_install do |installer|${fix}`))
    return config
  }])
}

const withKinwallKit = (config) =>
  withXcodeProjectBeta(config, (config) => {
    const project = config.modResults
    const root = project.rootObject
    const pkg = XCLocalSwiftPackageReference.create(project, { relativePath: '../KinwallKit' })
    root.props.packageReferences = [...(root.props.packageReferences ?? []), pkg]
    for (const target of root.props.targets) {
      if (!PBXNativeTarget.is(target)) continue
      const dep = XCSwiftPackageProductDependency.create(project, { package: pkg, productName: 'KinwallKit' })
      target.props.packageProductDependencies = [...(target.props.packageProductDependencies ?? []), dep]
      target.getFrameworksBuildPhase().props.files.push(PBXBuildFile.create(project, { productRef: dep }))
    }
    // One version for the app and every extension (App Store Connect wants them equal); the
    // Info.plists read these, so `CURRENT_PROJECT_VERSION=…` on the xcodebuild line sets them all.
    for (const target of root.props.targets) {
      for (const c of target.props.buildConfigurationList.props.buildConfigurations) {
        c.props.buildSettings.MARKETING_VERSION = config.version
        c.props.buildSettings.CURRENT_PROJECT_VERSION = config.ios?.buildNumber ?? '1'
      }
    }
    const app = root.getMainAppTarget('ios')
    const dir = path.join(config.modRequest.projectRoot, 'native/ios')
    for (const file of fs.readdirSync(dir).filter((f) => f.endsWith('.swift'))) {
      const ref = PBXFileReference.create(project, { path: `../native/ios/${file}`, sourceTree: 'SOURCE_ROOT', lastKnownFileType: 'sourcecode.swift' })
      root.props.mainGroup.props.children.push(ref)
      app.getSourcesBuildPhase().ensureFile({ fileRef: ref })
    }
    return config
  })

// The app's own Info.plist follows the build setting too; and no push entitlement (expo-notifications
// adds one): reminders are local, and a Personal Team can't sign push.
const withLocalOnly = (config) => {
  config = withInfoPlist(config, (c) => { c.modResults.CFBundleVersion = '$(CURRENT_PROJECT_VERSION)'; return c })
  return withEntitlementsPlist(config, (c) => { delete c.modResults['aps-environment']; return c })
}

// iOS 27 kills apps built with its SDK at launch unless they use the scene life cycle (the
// simulator only warns). Expo ships the scene delegate; the prebuild template's AppDelegate doesn't
// use it yet, so hand window creation to it: declare the scene, and stop starting React Native in
// the app delegate. Drop this once the template does it.
const withSceneLifecycle = (config) => {
  config = withInfoPlist(config, (c) => {
    c.modResults.UIApplicationSceneManifest = {
      UIApplicationSupportsMultipleScenes: false,
      UISceneConfigurations: {
        UIWindowSceneSessionRoleApplication: [
          { UISceneConfigurationName: 'Default Configuration', UISceneDelegateClassName: 'EXExpoAppSceneDelegate' },
        ],
      },
    }
    return c
  })
  return withAppDelegate(config, (c) => {
    let src = c.modResults.contents
    if (!src.includes('ExpoReactNativeFactoryProvider')) {
      src = src.replace('class AppDelegate: ExpoAppDelegate {', 'class AppDelegate: ExpoAppDelegate, ExpoReactNativeFactoryProvider {')
      src = src.replace(/\n#if os\(iOS\) \|\| os\(tvOS\)\n\s*window = UIWindow\(frame: UIScreen\.main\.bounds\)\n\s*factory\.startReactNative\([\s\S]*?\)\n#endif\n/, '\n')
      if (src.includes('startReactNative')) throw new Error('withSceneLifecycle: the AppDelegate template changed; update the patch')
    }
    c.modResults.contents = src
    return c
  })
}

// Android's share sheet: "Kinwall" takes shared text (a browser shares a page as its link), and
// MainActivity turns it into the app link the JavaScript already routes (src/App.tsx routeFor),
// family.kinwall.app:/open?to=recipes/import&url=<first link in the text>, before React Native
// reads the intent. The iOS equivalent is targets/share.
const SHARE_KOTLIN = String.raw`
  // A shared link (ACTION_SEND text) becomes family.kinwall.app:/open?to=recipes/import&url=<link>.
  private fun shareToLink(intent: Intent?) {
    if (intent?.action != Intent.ACTION_SEND) return
    val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
    val link = Regex("https?://[^\\s<>\"]+").find(text)?.value?.trimEnd('.', ',', ')', '!', '?', ';', ':', '\'', '"') ?: return
    intent.action = Intent.ACTION_VIEW
    intent.data = Uri.parse("family.kinwall.app:/open?to=recipes%2Fimport&url=" + Uri.encode(link))
  }

  override fun onNewIntent(intent: Intent) {
    shareToLink(intent)
    super.onNewIntent(intent)
  }
`
const withShareIntent = (config) => {
  config = withAndroidManifest(config, (c) => {
    const activity = AndroidConfig.Manifest.getMainActivityOrThrow(c.modResults)
    const filters = (activity['intent-filter'] ??= [])
    if (!filters.some((f) => f.action?.some((a) => a.$['android:name'] === 'android.intent.action.SEND'))) {
      filters.push({ action: [{ $: { 'android:name': 'android.intent.action.SEND' } }], category: [{ $: { 'android:name': 'android.intent.category.DEFAULT' } }], data: [{ $: { 'android:mimeType': 'text/plain' } }] })
    }
    return c
  })
  return withMainActivity(config, (c) => {
    let src = c.modResults.contents
    if (src.includes('shareToLink')) return c
    if (c.modResults.language !== 'kt' || !src.includes('super.onCreate(')) throw new Error('withShareIntent: the MainActivity template changed; update the patch')
    src = src.replace(/\nimport android\.os\.Bundle\n/, '\nimport android.content.Intent\nimport android.net.Uri\nimport android.os.Bundle\n')
    src = src.replace(/(\n\s*)super\.onCreate\(/, '$1shareToLink(intent)$1super.onCreate(')
    src = src.replace(/\n}\s*$/, `\n${SHARE_KOTLIN}}\n`)
    c.modResults.contents = src
    return c
  })
}

// Mods run newest-first, so register ours before apple-targets' and it runs once the targets exist.
module.exports = (config) => withTargets(withKinwallKit(withLocalOnly(withSceneLifecycle(withSpacesInPath(withShareIntent(config))))), {})
