#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint live_updates.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'live_updates'
  s.version          = '0.1.1'
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
  s.platform = :ios, '17.2'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'live_updates_privacy' => ['live_updates/Sources/live_updates/PrivacyInfo.xcprivacy']}
end
