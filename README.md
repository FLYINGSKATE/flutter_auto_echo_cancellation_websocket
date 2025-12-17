# Flutter Auto Echo Cancellation WebSocket

[![pub package](https://img.shields.io/pub/v/flutter_auto_echo_cancellation_websocket.svg)](https://pub.dev/packages/flutter_auto_echo_cancellation_websocket)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Flutter plugin for real-time voice communication with **automatic echo cancellation (AEC)** over WebSocket. Perfect for building voice agents, real-time voice chat, and AI voice assistants.

## ✨ Features

- 🎤 **Native AEC** - Hardware-level echo cancellation on iOS and Android
- 🔊 **Full Duplex Audio** - Simultaneous recording and playback
- 🌐 **WebSocket Streaming** - Real-time audio streaming over WebSocket
- 📱 **Cross-Platform** - iOS and Android support
- 🔇 **Audio Controls** - Mute/unmute, speaker control
- 📊 **Audio Levels** - Real-time input/output level monitoring
- 🔄 **Auto Reconnect** - Automatic reconnection on connection loss
- 📝 **Transcripts** - Support for speech-to-text transcripts

## 🎯 Why This Plugin?

Standard audio recording in Flutter doesn't include echo cancellation. When building voice agents or real-time voice chat, the microphone picks up the speaker output, creating an echo feedback loop. This plugin solves that by using native platform APIs that provide hardware-level AEC.

### The Problem

```
❌ Without AEC:
Microphone captures speaker output → Echo feedback → Agent hears itself

✅ With This Plugin:
VoiceProcessingIO (iOS) / AcousticEchoCanceler (Android) → Clean audio
```

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_auto_echo_cancellation_websocket: ^1.0.0
```

### iOS Setup

Add to your `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for voice communication</string>
```

### Android Setup

Add to your `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
```

## 🚀 Quick Start

```dart
import 'package:flutter_auto_echo_cancellation_websocket/flutter_auto_echo_cancellation_websocket.dart';

// Create plugin instance
final voicePlugin = VoicePlugin();

// Listen to events
voicePlugin.eventStream.listen((event) {
  if (event is TranscriptEvent) {
    print('${event.isUser ? "User" : "Agent"}: ${event.text}');
  } else if (event is ConnectionStateEvent) {
    print('Connection: ${event.state}');
  } else if (event is AgentStateEvent) {
    print('Agent: ${event.state}');
  }
});

// Connect to your voice server
await voicePlugin.connect(VoicePluginConfig(
  endpoint: 'wss://your-voice-server.com/websocket',
  agentId: 'your-agent-id',
  publicKey: 'your-public-key',
  metadata: {
    'user_id': 'user-123',
    'name': 'John Doe',
  },
));

// Control audio
await voicePlugin.setMicrophoneMuted(true);
await voicePlugin.setSpeakerMuted(false);

// Disconnect when done
voicePlugin.disconnect();
voicePlugin.dispose();
```

## 📖 API Reference

### VoicePlugin

The main class for voice communication.

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `connectionState` | `VoiceConnectionState` | Current connection state |
| `agentState` | `VoiceAgentState` | Current agent state |
| `isConnected` | `bool` | Whether connected to server |
| `isMicrophoneMuted` | `bool` | Whether microphone is muted |
| `isSpeakerMuted` | `bool` | Whether speaker is muted |
| `isAECEnabled` | `bool` | Whether AEC is active |
| `isAECSupported` | `bool` | Whether device supports AEC |
| `eventStream` | `Stream<VoicePluginEvent>` | Stream of plugin events |

#### Methods

| Method | Description |
|--------|-------------|
| `connect(config)` | Connect to voice server |
| `disconnect()` | Disconnect from server |
| `setMicrophoneMuted(muted)` | Mute/unmute microphone |
| `setSpeakerMuted(muted)` | Mute/unmute speaker |
| `toggleMicrophoneMute()` | Toggle microphone mute |
| `toggleSpeakerMute()` | Toggle speaker mute |
| `setSpeakerphoneOn(on)` | Switch between speaker/earpiece |
| `clearPlaybackBuffer()` | Clear audio playback buffer |
| `sendEvent(type, data)` | Send custom event to server |
| `getAudioInfo()` | Get audio configuration info |
| `checkAECAvailability()` | Check if AEC is available |
| `dispose()` | Release all resources |

### VoicePluginConfig

Configuration for connecting to the voice server.

```dart
VoicePluginConfig(
  // Required
  endpoint: 'wss://your-server.com/websocket',
  agentId: 'your-agent-id',
  publicKey: 'your-public-key',
  
  // Optional
  metadata: {'user_id': 'user-123'},
  includeMetadataInPrompt: true,
  sampleRate: 16000,
  channels: 1,
  audioQuality: AudioQuality.standard,
  enableNoiseSuppression: true,
  enableAutoGainControl: true,
  bufferDurationMs: 20,
  connectionTimeoutSeconds: 30,
  autoReconnect: true,
  maxReconnectAttempts: 3,
  reconnectDelayMs: 1000,
  enableDebugLogs: false,
)
```

### Events

Listen to events via the `eventStream`:

| Event | Description |
|-------|-------------|
| `ConnectionStateEvent` | Connection state changed |
| `AgentStateEvent` | Agent state changed |
| `TranscriptEvent` | Speech transcript received |
| `ErrorEvent` | Error occurred |
| `SessionReadyEvent` | Session is ready |
| `SessionEndedEvent` | Session ended |
| `AudioLevelEvent` | Audio level update |
| `AECStatusEvent` | AEC status changed |

## 🏗️ Architecture

### iOS Implementation

Uses **VoiceProcessingIO** Audio Unit for hardware AEC:

```
┌─────────────────────────────────────────┐
│       VoiceProcessingIO Audio Unit      │
│   ┌───────────┐       ┌───────────┐    │
│   │    Mic    │       │  Speaker  │    │
│   │   Input   │       │  Output   │    │
│   └─────┬─────┘       └─────┬─────┘    │
│         │   AEC CORRELATES  │          │
│         │   BOTH STREAMS    │          │
│         ▼                   ▼          │
│   ┌─────────────────────────────┐      │
│   │  Echo Cancellation Engine   │      │
│   └─────────────────────────────┘      │
└─────────────────────────────────────────┘
```

### Android Implementation

Uses **AudioRecord** with `VOICE_COMMUNICATION` source and **AcousticEchoCanceler**:

```
┌─────────────────────────────────────────┐
│    AudioRecord (VOICE_COMMUNICATION)    │
│              +                          │
│    AcousticEchoCanceler                 │
│              +                          │
│    AudioTrack (same session ID)         │
└─────────────────────────────────────────┘
```

## 🧪 Testing Checklist

- [ ] iOS: No echo when agent speaks
- [ ] iOS: Clear audio capture from microphone
- [ ] iOS: Works with speaker (not just earpiece)
- [ ] Android: No echo when agent speaks
- [ ] Android: AEC enabled on device
- [ ] Both: Metadata received by agent
- [ ] Both: Transcripts work correctly
- [ ] Both: Auto-reconnection works
- [ ] Both: Clean disconnect without artifacts

## 📱 Supported Platforms

| Platform | Minimum Version | AEC Method |
|----------|----------------|------------|
| iOS | 12.0+ | VoiceProcessingIO |
| Android | API 21+ | AcousticEchoCanceler |

## 🤝 Contributing

Contributions are welcome! Please read our [contributing guidelines](CONTRIBUTING.md) first.

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 👤 Author

**Ashraf K Salim**

- GitHub: [@FLYINGSKATE](https://github.com/FLYINGSKATE)
- LinkedIn: [ashrafksalim](https://www.linkedin.com/in/ashrafksalim/)
- Email: ashrafk.salim@gmail.com

## 🙏 Acknowledgments

- [Apple VoiceProcessingIO Documentation](https://developer.apple.com/documentation/audiotoolbox/kaudiounitsubtype_voiceprocessingio)
- [Android AcousticEchoCanceler](https://developer.android.com/reference/android/media/audiofx/AcousticEchoCanceler)
