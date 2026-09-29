Pod::Spec.new do |s|
  s.name           = 'KinwallNative'
  s.version        = '0.1.0'
  s.summary        = 'Kinwall: WidgetKit reloads, Live Activities and the Apple Watch link'
  s.author         = 'Kinwall'
  s.homepage       = 'https://github.com/JohnDuprey/kinwall-mobile'
  s.license        = 'AGPL-3.0'
  s.platforms      = { :ios => '17.0' }
  s.source         = { git: '' }
  s.static_framework = true
  s.dependency 'ExpoModulesCore'
  s.frameworks = 'WidgetKit', 'WatchConnectivity', 'ActivityKit'
  s.source_files = '**/*.swift'
end
