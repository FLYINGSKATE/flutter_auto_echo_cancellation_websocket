import 'voice_plugin_enums.dart';

/// Base class for all voice plugin events
abstract class VoicePluginEvent {
  const VoicePluginEvent();
}

/// Event when connection state changes
class ConnectionStateEvent extends VoicePluginEvent {
  final VoiceConnectionState state;
  final String? reason;

  const ConnectionStateEvent(this.state, {this.reason});

  @override
  String toString() => 'ConnectionStateEvent(state: $state, reason: $reason)';
}

/// Event when agent state changes
class AgentStateEvent extends VoicePluginEvent {
  final VoiceAgentState state;

  const AgentStateEvent(this.state);

  @override
  String toString() => 'AgentStateEvent(state: $state)';
}

/// Event when a transcript is received
class TranscriptEvent extends VoicePluginEvent {
  /// The transcribed text
  final String text;

  /// Whether this is from the user (true) or agent (false)
  final bool isUser;

  /// Whether this is a final transcript or interim
  final bool isFinal;

  /// Confidence score (0.0 to 1.0) if available
  final double? confidence;

  /// Timestamp of the transcript
  final DateTime timestamp;

  const TranscriptEvent({
    required this.text,
    required this.isUser,
    this.isFinal = true,
    this.confidence,
    required this.timestamp,
  });

  @override
  String toString() =>
      'TranscriptEvent(text: $text, isUser: $isUser, isFinal: $isFinal)';
}

/// Event when an error occurs
class ErrorEvent extends VoicePluginEvent {
  final String code;
  final String message;
  final dynamic details;
  final bool isFatal;

  const ErrorEvent({
    required this.code,
    required this.message,
    this.details,
    this.isFatal = false,
  });

  @override
  String toString() =>
      'ErrorEvent(code: $code, message: $message, isFatal: $isFatal)';
}

/// Event when session is ready
class SessionReadyEvent extends VoicePluginEvent {
  final String? sessionId;

  const SessionReadyEvent({this.sessionId});

  @override
  String toString() => 'SessionReadyEvent(sessionId: $sessionId)';
}

/// Event when session ends
class SessionEndedEvent extends VoicePluginEvent {
  final String? reason;
  final int? duration;

  const SessionEndedEvent({this.reason, this.duration});

  @override
  String toString() =>
      'SessionEndedEvent(reason: $reason, duration: $duration)';
}

/// Event with audio level information
class AudioLevelEvent extends VoicePluginEvent {
  /// Audio level from 0.0 (silence) to 1.0 (max)
  final double level;

  /// Whether this is input (microphone) or output (speaker)
  final bool isInput;

  const AudioLevelEvent({
    required this.level,
    required this.isInput,
  });

  @override
  String toString() => 'AudioLevelEvent(level: $level, isInput: $isInput)';
}

/// Event when AEC status changes
class AECStatusEvent extends VoicePluginEvent {
  final bool isEnabled;
  final bool isSupported;
  final String? aecType;

  const AECStatusEvent({
    required this.isEnabled,
    required this.isSupported,
    this.aecType,
  });

  @override
  String toString() =>
      'AECStatusEvent(isEnabled: $isEnabled, isSupported: $isSupported, type: $aecType)';
}
