Pod::Spec.new do |spec|
  spec.name = 'LumenKit'
  spec.version = '0.1.0'
  spec.summary = 'Reusable formatting, SwiftUI, refresh and media components.'
  spec.homepage = 'https://github.com/ZMsQRT/LumenKit'
  spec.license = { :type => 'Proprietary' }
  spec.author = 'LumenKit contributors'
  spec.source = { :git => 'https://github.com/ZMsQRT/LumenKit.git', :tag => spec.version.to_s }
  spec.ios.deployment_target = '17.0'
  spec.swift_version = '6.0'
  spec.static_framework = true
  spec.source_files = 'Sources/**/*.swift'
  spec.frameworks = 'SwiftUI', 'UIKit', 'Foundation', 'AVFoundation', 'CoreImage', 'CryptoKit'
end
