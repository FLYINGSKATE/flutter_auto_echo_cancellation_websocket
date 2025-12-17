/// Flutter Auto Echo Cancellation WebSocket Plugin
///
/// A Flutter plugin for real-time voice communication with automatic
/// echo cancellation (AEC) over WebSocket.
///
/// Features:
/// - Native AEC on iOS using VoiceProcessingIO Audio Unit
/// - Native AEC on Android using AcousticEchoCanceler
/// - WebSocket-based audio streaming
/// - Support for metadata and custom configurations
/// - Transcript callbacks for both user and agent speech
///
/// Author: Ashraf K Salim
/// Email: ashrafk.salim@gmail.com
/// GitHub: https://github.com/FLYINGSKATE
/// LinkedIn: https://www.linkedin.com/in/ashrafksalim/

library flutter_auto_echo_cancellation_websocket;

export 'src/voice_plugin.dart';
export 'src/voice_plugin_config.dart';
export 'src/voice_plugin_enums.dart';
export 'src/voice_plugin_events.dart';
