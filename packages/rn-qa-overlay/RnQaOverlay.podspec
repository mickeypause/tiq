require 'json'
package = JSON.parse(File.read(File.join(__dir__, 'package.json')))
Pod::Spec.new do |s|
  s.name = 'RnQaOverlay'
  s.version = package['version']
  s.summary = package['description']
  s.description = package['description']
  s.license = { :type => 'Custom', :file => 'LICENSE' }
  s.author = 'rn-qa-overlay contributors'
  s.homepage = "https://www.npmjs.com/package/#{package['name']}"
  s.source = { :http => "https://registry.npmjs.org/#{package['name']}/-/#{package['name'].split('/').last}-#{s.version}.tgz" }
  s.platform = :ios, '16.4'
  s.swift_version = '5.9'
  s.static_framework = true
  s.source_files = 'ios/**/*.swift'
  s.resource_bundles = { 'QaLinearIcons' => ['ios/LinearIcons.xcassets'] }
  s.dependency 'ExpoModulesCore'
  s.frameworks = 'SwiftUI', 'PhotosUI', 'ReplayKit', 'AVFoundation', 'AVKit'
end
