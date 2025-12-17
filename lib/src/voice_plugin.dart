import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'voice_plugin_config.dart';
import 'voice_plugin_enums.dart';
import 'voice_plugin_events.dart';

/// Flutter Auto Echo Cancellation WebSocket Plugin
///
/// A plugin for real-time voice communication with automatic echo cancellation.
///
/// Example usage:
/// ```dart
/// final plugin = VoicePlugin();
///
/// // Listen to events
/// plugin.eventStream.listen((event) {
///   if (event is TranscriptEvent) {
///     print('${event.isUser ? "User" : "Agent"}: ${event.text}');
///   }
/// });
///
/// // Connect
/// await plugin.connect(VoicePluginConfig(
///   endpoint: 'wss://your-server.com/voice',
///   agentId: 'your-agent-id',
///   publicKey: 'your-public-key',
/// ));
/// ```
class VoicePlugin {
  static const String _channelName = 'flutter_auto_echo_cancellation_websocket';
  static const String _eventChannelName =
      'flutter_auto_echo_cancellation_websocket/events';

  static const MethodChannel _channel = MethodChannel(_channelName);
  static const EventChannel _eventChannel = EventChannel(_eventChannelName);

  // State
  VoiceConnectionState _connectionState = VoiceConnectionState.disconnected;
  VoiceAgentState _agentState = VoiceAgentState.idle;
  bool _isMicrophoneMuted = false;
  bool _isSpeakerMuted = false;
  bool _isAECEnabled = false;
  bool _isAECSupported = false;

  // Event stream controller
  final StreamController<VoicePluginEvent> _eventController =
      StreamController<VoicePluginEvent>.broadcast();

  // Native event subscription
  StreamSubscription? _nativeEventSubscription;

  // Configuration
  VoicePluginConfig? _config;

  // Callbacks (alternative to stream)
  void Function(VoiceConnectionState state, String? reason)?
      onConnectionStateChanged;
  void Function(VoiceAgentState state)? onAgentStateChanged;
  void Function(String text, bool isUser, bool isFinal)? onTranscript;
  void Function(String code, String message, bool isFatal)? onError;
  void Function(String? sessionId)? onReady;
  void Function(String? reason)? onSessionEnded;
  void Function(double level, bool isInput)? onAudioLevel;

  /// Creates a new VoicePlugin instance
  VoicePlugin() {
    _setupEventListener();
  }

  // Getters
  /// Current connection state
  VoiceConnectionState get connectionState => _connectionState;

  /// Current agent state
  VoiceAgentState get agentState => _agentState;

  /// Whether connected to the server
  bool get isConnected => _connectionState == VoiceConnectionState.connected;

  /// Whether microphone is muted
  bool get isMicrophoneMuted => _isMicrophoneMuted;

  /// Whether speaker is muted
  bool get isSpeakerMuted => _isSpeakerMuted;

  /// Whether AEC is currently enabled
  bool get isAECEnabled => _isAECEnabled;

  /// Whether AEC is supported on this device
  bool get isAECSupported => _isAECSupported;

  /// Current configuration
  VoicePluginConfig? get config => _config;

  /// Stream of voice plugin events
  Stream<VoicePluginEvent> get eventStream => _eventController.stream;

  /// Sets up the native event listener
  void _setupEventListener() {
    _nativeEventSubscription = _eventChannel
        .receiveBroadcastStream()
        .listen(_handleNativeEvent, onError: _handleNativeError);
  }

  /// Handles events from native code
  void _handleNativeEvent(dynamic event) {
    if (event is! Map) return;

    final type = event['type'] as String?;

    switch (type) {
      case 'connected':
        _updateConnectionState(VoiceConnectionState.connected);
        break;

      case 'connecting':
        _updateConnectionState(VoiceConnectionState.connecting);
        break;

      case 'disconnected':
        final reason = event['reason'] as String?;
        _updateConnectionState(VoiceConnectionState.disconnected, reason);
        _updateAgentState(VoiceAgentState.idle);
        break;

      case 'failed':
        final reason = event['reason'] as String?;
        _updateConnectionState(VoiceConnectionState.failed, reason);
        break;

      case 'reconnecting':
        _updateConnectionState(VoiceConnectionState.reconnecting);
        break;

      case 'ready':
        final sessionId = event['sessionId'] as String?;
        _updateAgentState(VoiceAgentState.listening);
        _eventController.add(SessionReadyEvent(sessionId: sessionId));
        onReady?.call(sessionId);
        break;

      case 'agentState':
        final state = event['state'] as String?;
        switch (state) {
          case 'listening':
            _updateAgentState(VoiceAgentState.listening);
            break;
          case 'speaking':
            _updateAgentState(VoiceAgentState.speaking);
            break;
          case 'paused':
            _updateAgentState(VoiceAgentState.paused);
            break;
          case 'thinking':
            _updateAgentState(VoiceAgentState.thinking);
            break;
          case 'idle':
            _updateAgentState(VoiceAgentState.idle);
            break;
        }
        break;

      case 'transcript':
        final text = event['text'] as String?;
        final speaker = event['speaker'] as String?;
        final isFinal = event['isFinal'] as bool? ?? true;
        final confidence = event['confidence'] as double?;
        if (text != null) {
          final isUser = speaker == 'user';
          _eventController.add(TranscriptEvent(
            text: text,
            isUser: isUser,
            isFinal: isFinal,
            confidence: confidence,
            timestamp: DateTime.now(),
          ));
          onTranscript?.call(text, isUser, isFinal);
        }
        break;

      case 'sessionEnded':
        final reason = event['reason'] as String?;
        final duration = event['duration'] as int?;
        _updateConnectionState(VoiceConnectionState.disconnected);
        _updateAgentState(VoiceAgentState.idle);
        _eventController.add(SessionEndedEvent(reason: reason, duration: duration));
        onSessionEnded?.call(reason);
        break;

      case 'error':
        final code = event['code'] as String? ?? 'UNKNOWN';
        final message = event['message'] as String? ?? 'Unknown error';
        final isFatal = event['isFatal'] as bool? ?? false;
        final details = event['details'];
        _eventController.add(ErrorEvent(
          code: code,
          message: message,
          details: details,
          isFatal: isFatal,
        ));
        onError?.call(code, message, isFatal);
        break;

      case 'audioLevel':
        final level = (event['level'] as num?)?.toDouble() ?? 0.0;
        final isInput = event['isInput'] as bool? ?? true;
        _eventController.add(AudioLevelEvent(level: level, isInput: isInput));
        onAudioLevel?.call(level, isInput);
        break;

      case 'aecStatus':
        final isEnabled = event['isEnabled'] as bool? ?? false;
        final isSupported = event['isSupported'] as bool? ?? false;
        final aecType = event['aecType'] as String?;
        _isAECEnabled = isEnabled;
        _isAECSupported = isSupported;
        _eventController.add(AECStatusEvent(
          isEnabled: isEnabled,
          isSupported: isSupported,
          aecType: aecType,
        ));
        break;
    }
  }

  /// Handles errors from native code
  void _handleNativeError(dynamic error) {
    final errorEvent = ErrorEvent(
      code: 'NATIVE_ERROR',
      message: error.toString(),
      isFatal: true,
    );
    _eventController.add(errorEvent);
    onError?.call('NATIVE_ERROR', error.toString(), true);
  }

  /// Updates the connection state and notifies listeners
  void _updateConnectionState(VoiceConnectionState state, [String? reason]) {
    if (_connectionState != state) {
      _connectionState = state;
      _eventController.add(ConnectionStateEvent(state, reason: reason));
      onConnectionStateChanged?.call(state, reason);
    }
  }

  /// Updates the agent state and notifies listeners
  void _updateAgentState(VoiceAgentState state) {
    if (_agentState != state) {
      _agentState = state;
      _eventController.add(AgentStateEvent(state));
      onAgentStateChanged?.call(state);
    }
  }

  /// Connect to the voice service
  ///
  /// Returns `true` if connection was initiated successfully.
  Future<bool> connect(VoicePluginConfig config) async {
    _config = config;
    _updateConnectionState(VoiceConnectionState.connecting);

    try {
      final result = await _channel.invokeMethod('connect', config.toMap());
      return result == true;
    } catch (e) {
      _updateConnectionState(VoiceConnectionState.failed, e.toString());
      _eventController.add(ErrorEvent(
        code: 'CONNECT_ERROR',
        message: e.toString(),
        isFatal: true,
      ));
      onError?.call('CONNECT_ERROR', e.toString(), true);
      return false;
    }
  }

  /// Disconnect from the voice service
  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('disconnect');
    } catch (e) {
      _eventController.add(ErrorEvent(
        code: 'DISCONNECT_ERROR',
        message: e.toString(),
      ));
      onError?.call('DISCONNECT_ERROR', e.toString(), false);
    }
  }

  /// Mute or unmute the microphone
  Future<void> setMicrophoneMuted(bool muted) async {
    try {
      await _channel.invokeMethod('setMicrophoneMuted', {'muted': muted});
      _isMicrophoneMuted = muted;
    } catch (e) {
      _eventController.add(ErrorEvent(
        code: 'MUTE_ERROR',
        message: e.toString(),
      ));
      onError?.call('MUTE_ERROR', e.toString(), false);
    }
  }

  /// Mute or unmute the speaker
  Future<void> setSpeakerMuted(bool muted) async {
    try {
      await _channel.invokeMethod('setSpeakerMuted', {'muted': muted});
      _isSpeakerMuted = muted;
    } catch (e) {
      _eventController.add(ErrorEvent(
        code: 'SPEAKER_ERROR',
        message: e.toString(),
      ));
      onError?.call('SPEAKER_ERROR', e.toString(), false);
    }
  }

  /// Toggle microphone mute state
  Future<void> toggleMicrophoneMute() async {
    await setMicrophoneMuted(!_isMicrophoneMuted);
  }

  /// Toggle speaker mute state
  Future<void> toggleSpeakerMute() async {
    await setSpeakerMuted(!_isSpeakerMuted);
  }

  /// Set the audio output to speaker or earpiece
  Future<void> setSpeakerphoneOn(bool on) async {
    try {
      await _channel.invokeMethod('setSpeakerphoneOn', {'on': on});
    } catch (e) {
      _eventController.add(ErrorEvent(
        code: 'SPEAKER_ERROR',
        message: e.toString(),
      ));
      onError?.call('SPEAKER_ERROR', e.toString(), false);
    }
  }

  /// Clear the audio playback buffer (useful when interrupting)
  Future<void> clearPlaybackBuffer() async {
    try {
      await _channel.invokeMethod('clearPlaybackBuffer');
    } catch (e) {
      debugPrint('Error clearing playback buffer: $e');
    }
  }

  /// Send a custom event to the server
  Future<void> sendEvent(String eventType, Map<String, dynamic>? data) async {
    try {
      await _channel.invokeMethod('sendEvent', {
        'eventType': eventType,
        'data': data,
      });
    } catch (e) {
      _eventController.add(ErrorEvent(
        code: 'SEND_EVENT_ERROR',
        message: e.toString(),
      ));
      onError?.call('SEND_EVENT_ERROR', e.toString(), false);
    }
  }

  /// Get information about the current audio configuration
  Future<Map<String, dynamic>?> getAudioInfo() async {
    try {
      final result = await _channel.invokeMethod('getAudioInfo');
      return result as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }

  /// Check if AEC is available on this device
  Future<bool> checkAECAvailability() async {
    try {
      final result = await _channel.invokeMethod('checkAECAvailability');
      _isAECSupported = result == true;
      return _isAECSupported;
    } catch (e) {
      return false;
    }
  }

  /// Dispose the plugin and release resources
  void dispose() {
    _nativeEventSubscription?.cancel();
    _eventController.close();
    disconnect();
  }
}
