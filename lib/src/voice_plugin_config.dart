import 'voice_plugin_enums.dart';

/// Configuration for the voice plugin
class VoicePluginConfig {
  /// WebSocket endpoint URL
  final String endpoint;

  /// Agent ID for the voice service
  final String agentId;

  /// Public key for authentication
  final String publicKey;

  /// Custom metadata to send with the connection
  final Map<String, dynamic>? metadata;

  /// Whether to include metadata in the AI prompt
  final bool includeMetadataInPrompt;

  /// Audio sample rate in Hz (default: 16000)
  final int sampleRate;

  /// Number of audio channels (default: 1 for mono)
  final int channels;

  /// Audio quality setting
  final AudioQuality audioQuality;

  /// Enable noise suppression (if available on device)
  final bool enableNoiseSuppression;

  /// Enable automatic gain control (if available on device)
  final bool enableAutoGainControl;

  /// Buffer duration in milliseconds (affects latency)
  final int bufferDurationMs;

  /// Connection timeout in seconds
  final int connectionTimeoutSeconds;

  /// Enable automatic reconnection on disconnect
  final bool autoReconnect;

  /// Maximum reconnection attempts
  final int maxReconnectAttempts;

  /// Delay between reconnection attempts in milliseconds
  final int reconnectDelayMs;

  /// Enable debug logging
  final bool enableDebugLogs;

  const VoicePluginConfig({
    required this.endpoint,
    required this.agentId,
    required this.publicKey,
    this.metadata,
    this.includeMetadataInPrompt = true,
    this.sampleRate = 16000,
    this.channels = 1,
    this.audioQuality = AudioQuality.standard,
    this.enableNoiseSuppression = true,
    this.enableAutoGainControl = true,
    this.bufferDurationMs = 20,
    this.connectionTimeoutSeconds = 30,
    this.autoReconnect = true,
    this.maxReconnectAttempts = 3,
    this.reconnectDelayMs = 1000,
    this.enableDebugLogs = false,
  });

  /// Creates a copy of this config with the given fields replaced
  VoicePluginConfig copyWith({
    String? endpoint,
    String? agentId,
    String? publicKey,
    Map<String, dynamic>? metadata,
    bool? includeMetadataInPrompt,
    int? sampleRate,
    int? channels,
    AudioQuality? audioQuality,
    bool? enableNoiseSuppression,
    bool? enableAutoGainControl,
    int? bufferDurationMs,
    int? connectionTimeoutSeconds,
    bool? autoReconnect,
    int? maxReconnectAttempts,
    int? reconnectDelayMs,
    bool? enableDebugLogs,
  }) {
    return VoicePluginConfig(
      endpoint: endpoint ?? this.endpoint,
      agentId: agentId ?? this.agentId,
      publicKey: publicKey ?? this.publicKey,
      metadata: metadata ?? this.metadata,
      includeMetadataInPrompt:
          includeMetadataInPrompt ?? this.includeMetadataInPrompt,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      audioQuality: audioQuality ?? this.audioQuality,
      enableNoiseSuppression:
          enableNoiseSuppression ?? this.enableNoiseSuppression,
      enableAutoGainControl:
          enableAutoGainControl ?? this.enableAutoGainControl,
      bufferDurationMs: bufferDurationMs ?? this.bufferDurationMs,
      connectionTimeoutSeconds:
          connectionTimeoutSeconds ?? this.connectionTimeoutSeconds,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      maxReconnectAttempts: maxReconnectAttempts ?? this.maxReconnectAttempts,
      reconnectDelayMs: reconnectDelayMs ?? this.reconnectDelayMs,
      enableDebugLogs: enableDebugLogs ?? this.enableDebugLogs,
    );
  }

  /// Converts config to a map for native code
  Map<String, dynamic> toMap() {
    return {
      'endpoint': endpoint,
      'agentId': agentId,
      'publicKey': publicKey,
      'metadata': metadata,
      'includeMetadataInPrompt': includeMetadataInPrompt,
      'sampleRate': sampleRate,
      'channels': channels,
      'audioQuality': audioQuality.index,
      'enableNoiseSuppression': enableNoiseSuppression,
      'enableAutoGainControl': enableAutoGainControl,
      'bufferDurationMs': bufferDurationMs,
      'connectionTimeoutSeconds': connectionTimeoutSeconds,
      'autoReconnect': autoReconnect,
      'maxReconnectAttempts': maxReconnectAttempts,
      'reconnectDelayMs': reconnectDelayMs,
      'enableDebugLogs': enableDebugLogs,
    };
  }

  @override
  String toString() {
    return 'VoicePluginConfig(endpoint: $endpoint, agentId: $agentId, '
        'sampleRate: $sampleRate, audioQuality: $audioQuality)';
  }
}
