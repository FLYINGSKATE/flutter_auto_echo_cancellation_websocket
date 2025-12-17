import 'package:flutter/material.dart';
import 'package:flutter_auto_echo_cancellation_websocket/flutter_auto_echo_cancellation_websocket.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Plugin Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const VoiceScreen(),
    );
  }
}

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  final VoicePlugin _plugin = VoicePlugin();
  
  final List<TranscriptMessage> _transcripts = [];
  bool _isConnecting = false;
  String? _errorMessage;
  bool _aecEnabled = false;
  bool _aecSupported = false;
  double _inputLevel = 0;
  double _outputLevel = 0;

  @override
  void initState() {
    super.initState();
    _setupPlugin();
  }

  void _setupPlugin() {
    // Listen to the event stream
    _plugin.eventStream.listen((event) {
      if (event is ConnectionStateEvent) {
        setState(() {
          _isConnecting = event.state == VoiceConnectionState.connecting;
          if (event.state == VoiceConnectionState.failed) {
            _errorMessage = event.reason ?? 'Connection failed';
          }
        });
      } else if (event is AgentStateEvent) {
        setState(() {});
      } else if (event is TranscriptEvent) {
        setState(() {
          _transcripts.add(TranscriptMessage(
            text: event.text,
            isUser: event.isUser,
            timestamp: event.timestamp,
          ));
        });
      } else if (event is ErrorEvent) {
        setState(() {
          _errorMessage = event.message;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${event.message}'),
            backgroundColor: Colors.red,
          ),
        );
      } else if (event is AECStatusEvent) {
        setState(() {
          _aecEnabled = event.isEnabled;
          _aecSupported = event.isSupported;
        });
      } else if (event is AudioLevelEvent) {
        setState(() {
          if (event.isInput) {
            _inputLevel = event.level;
          } else {
            _outputLevel = event.level;
          }
        });
      }
    });
  }

  Future<void> _startCall() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
      _transcripts.clear();
    });

    final success = await _plugin.connect(
      VoicePluginConfig(
        // Replace with your actual WebSocket endpoint
        endpoint: 'wss://api-west.millis.ai:8080/millis',
        agentId: 'YOUR_AGENT_ID',
        publicKey: 'YOUR_PUBLIC_KEY',
        metadata: {
          'user_id': 'demo-user',
          'name': 'Demo User',
          'email': 'demo@example.com',
        },
        includeMetadataInPrompt: true,
        enableNoiseSuppression: true,
        enableAutoGainControl: true,
        autoReconnect: true,
        maxReconnectAttempts: 3,
      ),
    );

    if (!success) {
      setState(() {
        _isConnecting = false;
        _errorMessage = 'Failed to connect';
      });
    }
  }

  void _endCall() {
    _plugin.disconnect();
    setState(() {
      _inputLevel = 0;
      _outputLevel = 0;
    });
  }

  void _toggleMute() {
    _plugin.toggleMicrophoneMute();
    setState(() {});
  }

  void _toggleSpeaker() {
    _plugin.toggleSpeakerMute();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Voice Agent Demo'),
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            padding: const EdgeInsets.all(16),
            color: _getStatusColor(),
            child: Row(
              children: [
                Icon(
                  _getStatusIcon(),
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getStatusText(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_aecSupported)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _aecEnabled ? Colors.green : Colors.orange,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _aecEnabled ? 'AEC ON' : 'AEC OFF',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // Audio levels
          if (_plugin.isConnected) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text('Microphone'),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: _inputLevel,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _plugin.isMicrophoneMuted 
                                ? Colors.grey 
                                : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        const Text('Speaker'),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: _outputLevel,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _plugin.isSpeakerMuted 
                                ? Colors.grey 
                                : Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          // Transcripts
          Expanded(
            child: _transcripts.isEmpty
                ? Center(
                    child: Text(
                      _plugin.isConnected
                          ? 'Start speaking...'
                          : 'Press the button to start a call',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _transcripts.length,
                    itemBuilder: (context, index) {
                      final transcript = _transcripts[index];
                      return _buildTranscriptBubble(transcript);
                    },
                  ),
          ),
          
          // Error message
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red[100],
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _errorMessage = null),
                  ),
                ],
              ),
            ),
          
          // Control buttons
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (_plugin.isConnected) ...[
                  // Mute button
                  FloatingActionButton(
                    heroTag: 'mute',
                    onPressed: _toggleMute,
                    backgroundColor: _plugin.isMicrophoneMuted
                        ? Colors.red
                        : Colors.grey,
                    child: Icon(
                      _plugin.isMicrophoneMuted ? Icons.mic_off : Icons.mic,
                    ),
                  ),
                  
                  // End call button
                  FloatingActionButton.large(
                    heroTag: 'endCall',
                    onPressed: _endCall,
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.call_end, size: 36),
                  ),
                  
                  // Speaker button
                  FloatingActionButton(
                    heroTag: 'speaker',
                    onPressed: _toggleSpeaker,
                    backgroundColor: _plugin.isSpeakerMuted
                        ? Colors.red
                        : Colors.grey,
                    child: Icon(
                      _plugin.isSpeakerMuted
                          ? Icons.volume_off
                          : Icons.volume_up,
                    ),
                  ),
                ] else ...[
                  // Start call button
                  FloatingActionButton.large(
                    heroTag: 'startCall',
                    onPressed: _isConnecting ? null : _startCall,
                    backgroundColor: Colors.green,
                    child: _isConnecting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Icon(Icons.call, size: 36),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptBubble(TranscriptMessage transcript) {
    return Align(
      alignment:
          transcript.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: transcript.isUser
              ? Theme.of(context).colorScheme.primary
              : Colors.grey[300],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              transcript.text,
              style: TextStyle(
                color: transcript.isUser ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(transcript.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: transcript.isUser ? Colors.white70 : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (_plugin.connectionState) {
      case VoiceConnectionState.connected:
        return Colors.green;
      case VoiceConnectionState.connecting:
      case VoiceConnectionState.reconnecting:
        return Colors.orange;
      case VoiceConnectionState.failed:
        return Colors.red;
      case VoiceConnectionState.disconnected:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon() {
    switch (_plugin.agentState) {
      case VoiceAgentState.listening:
        return Icons.hearing;
      case VoiceAgentState.speaking:
        return Icons.record_voice_over;
      case VoiceAgentState.thinking:
        return Icons.psychology;
      case VoiceAgentState.paused:
        return Icons.pause;
      case VoiceAgentState.idle:
        return Icons.mic_none;
    }
  }

  String _getStatusText() {
    if (!_plugin.isConnected) {
      return _plugin.connectionState.toString().split('.').last;
    }
    return _plugin.agentState.toString().split('.').last;
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _plugin.dispose();
    super.dispose();
  }
}

class TranscriptMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  TranscriptMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}
