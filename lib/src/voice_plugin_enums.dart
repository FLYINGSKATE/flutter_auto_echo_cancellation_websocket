/// Connection states for the voice plugin
enum VoiceConnectionState {
  /// Not connected to the server
  disconnected,

  /// Currently attempting to connect
  connecting,

  /// Successfully connected and ready for communication
  connected,

  /// Connection attempt failed
  failed,

  /// Connection was lost and attempting to reconnect
  reconnecting,
}

/// States of the voice agent
enum VoiceAgentState {
  /// Agent is idle, not actively processing
  idle,

  /// Agent is listening for user speech
  listening,

  /// Agent is speaking/playing audio response
  speaking,

  /// Agent is temporarily paused
  paused,

  /// Agent is processing user input
  thinking,
}

/// Audio quality settings
enum AudioQuality {
  /// Low quality (8kHz sample rate) - lower bandwidth
  low,

  /// Standard quality (16kHz sample rate) - recommended
  standard,

  /// High quality (44.1kHz sample rate) - higher bandwidth
  high,
}

/// Supported audio codecs
enum AudioCodec {
  /// PCM 16-bit (default, most compatible)
  pcm16,

  /// Opus codec (better compression)
  opus,
}
