#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_auto_echo_cancellation_websocket.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_auto_echo_cancellation_websocket'
  s.version          = '1.0.0'
  s.summary          = 'Flutter plugin for real-time voice communication with automatic echo cancellation over WebSocket.'
  s.description      = <<-DESC
A Flutter plugin that provides real-time voice communication with native Acoustic Echo Cancellation (AEC) 
using VoiceProcessingIO on iOS. Supports WebSocket-based audio streaming for voice agent applications.
                       DESC
  s.homepage         = 'https://github.com/FLYINGSKATE/flutter_auto_echo_cancellation_websocket'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ashraf K Salim' => 'ashrafk.salim@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  
  # Required frameworks for audio processing
  s.frameworks = 'AVFoundation', 'AudioToolbox'
end
