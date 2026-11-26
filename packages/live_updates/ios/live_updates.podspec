#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint live_updates.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'live_updates'
  s.version          = '0.5.0'
  s.summary          = 'iOS Live Activities and Android Live Update notifications with one Dart API.'
  s.description      = <<-DESC
iOS Live Activities and Android Live Update notifications with one Dart API.
                       DESC
  s.homepage         = 'https://github.com/metal-president/live_updates'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Teruaki Kinoshita' => 'https://github.com/metal-president' }
  s.source           = { :path => '.' }
  s.source_files = 'live_updates/Sources/live_updates/**/*.swift', 'live_updates/Sources/live_updates_objc/**/*.{h,m}'
  s.public_header_files = 'live_updates/Sources/live_updates_objc/include/*.h'
  s.requires_arc = true
  s.resource_bundles = { 'live_updates_privacy' => ['live_updates/Sources/live_updates/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'

end
