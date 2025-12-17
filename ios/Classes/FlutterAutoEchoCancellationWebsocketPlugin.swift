import Flutter
import UIKit
import AVFoundation

public class FlutterAutoEchoCancellationWebsocketPlugin: NSObject, FlutterPlugin {
    
    private var audioEngine: AECAudioEngine?
    private var webSocketManager: WebSocketManager?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    
    // Playback state
    private var isPaused = false
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter_auto_echo_cancellation_websocket",
            binaryMessenger: registrar.messenger()
        )
        
        let eventChannel = FlutterEventChannel(
            name: "flutter_auto_echo_cancellation_websocket/events",
            binaryMessenger: registrar.messenger()
        )
        
        let instance = FlutterAutoEchoCancellationWebsocketPlugin()
        instance.eventChannel = eventChannel
        
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "connect":
            handleConnect(call, result: result)
            
        case "disconnect":
            handleDisconnect(result: result)
            
        case "setMicrophoneMuted":
            handleSetMicrophoneMuted(call, result: result)
            
        case "setSpeakerMuted":
            handleSetSpeakerMuted(call, result: result)
            
        case "setSpeakerphoneOn":
            handleSetSpeakerphoneOn(call, result: result)
            
        case "clearPlaybackBuffer":
            handleClearPlaybackBuffer(result: result)
            
        case "sendEvent":
            handleSendEvent(call, result: result)
            
        case "getAudioInfo":
            handleGetAudioInfo(result: result)
            
        case "checkAECAvailability":
            handleCheckAECAvailability(result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Connect
    
    private func handleConnect(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let endpoint = args["endpoint"] as? String,
              let agentId = args["agentId"] as? String,
              let publicKey = args["publicKey"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
            return
        }
        
        let metadata = args["metadata"] as? [String: Any]
        let includeMetadataInPrompt = args["includeMetadataInPrompt"] as? Bool ?? true
        let sampleRate = args["sampleRate"] as? Double ?? 16000
        let autoReconnect = args["autoReconnect"] as? Bool ?? true
        let maxReconnectAttempts = args["maxReconnectAttempts"] as? Int ?? 3
        let reconnectDelayMs = args["reconnectDelayMs"] as? Int ?? 1000
        let enableDebugLogs = args["enableDebugLogs"] as? Bool ?? false
        
        do {
            // Request microphone permission
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                guard let self = self else { return }
                
                if !granted {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "PERMISSION_DENIED", message: "Microphone permission denied", details: nil))
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    do {
                        try self.initializeAndConnect(
                            endpoint: endpoint,
                            agentId: agentId,
                            publicKey: publicKey,
                            metadata: metadata,
                            includeMetadataInPrompt: includeMetadataInPrompt,
                            sampleRate: sampleRate,
                            autoReconnect: autoReconnect,
                            maxReconnectAttempts: maxReconnectAttempts,
                            reconnectDelayMs: reconnectDelayMs,
                            enableDebugLogs: enableDebugLogs
                        )
                        result(true)
                    } catch {
                        result(FlutterError(code: "INIT_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    }
    
    private func initializeAndConnect(
        endpoint: String,
        agentId: String,
        publicKey: String,
        metadata: [String: Any]?,
        includeMetadataInPrompt: Bool,
        sampleRate: Double,
        autoReconnect: Bool,
        maxReconnectAttempts: Int,
        reconnectDelayMs: Int,
        enableDebugLogs: Bool
    ) throws {
        // Initialize audio engine with AEC
        audioEngine = AECAudioEngine(sampleRate: sampleRate)
        try audioEngine?.initialize()
        
        // Set up audio capture callback
        audioEngine?.onAudioCaptured = { [weak self] data in
            self?.webSocketManager?.sendAudio(data)
        }
        
        // Set up audio level callback
        audioEngine?.onAudioLevel = { [weak self] level, isInput in
            self?.sendEvent([
                "type": "audioLevel",
                "level": level,
                "isInput": isInput
            ])
        }
        
        // Send AEC status
        sendEvent([
            "type": "aecStatus",
            "isEnabled": true,
            "isSupported": true,
            "aecType": "VoiceProcessingIO"
        ])
        
        // Initialize WebSocket
        webSocketManager = WebSocketManager()
        
        webSocketManager?.onConnected = { [weak self] in
            self?.sendEvent(["type": "connected"])
        }
        
        webSocketManager?.onDisconnected = { [weak self] reason in
            self?.audioEngine?.stop()
            self?.sendEvent(["type": "disconnected", "reason": reason as Any])
        }
        
        webSocketManager?.onAudioReceived = { [weak self] data in
            guard let self = self, !self.isPaused else { return }
            self.audioEngine?.enqueueAudioForPlayback(data)
        }
        
        webSocketManager?.onError = { [weak self] code, message, isFatal in
            self?.sendEvent([
                "type": "error",
                "code": code,
                "message": message,
                "isFatal": isFatal
            ])
        }
        
        webSocketManager?.onEvent = { [weak self] method, data in
            self?.handleServerEvent(method, data: data)
        }
        
        // Connect
        webSocketManager?.connect(
            endpoint: endpoint,
            agentId: agentId,
            publicKey: publicKey,
            metadata: metadata,
            includeMetadataInPrompt: includeMetadataInPrompt,
            autoReconnect: autoReconnect,
            maxReconnectAttempts: maxReconnectAttempts,
            reconnectDelayMs: reconnectDelayMs
        )
        
        // Start audio engine
        try audioEngine?.start()
    }
    
    // MARK: - Disconnect
    
    private func handleDisconnect(result: @escaping FlutterResult) {
        webSocketManager?.disconnect()
        audioEngine?.stop()
        audioEngine?.dispose()
        
        webSocketManager = nil
        audioEngine = nil
        isPaused = false
        
        result(true)
    }
    
    // MARK: - Mute Controls
    
    private func handleSetMicrophoneMuted(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let muted = args["muted"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing muted argument", details: nil))
            return
        }
        
        audioEngine?.setMicrophoneMuted(muted)
        result(true)
    }
    
    private func handleSetSpeakerMuted(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let muted = args["muted"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing muted argument", details: nil))
            return
        }
        
        audioEngine?.setSpeakerMuted(muted)
        result(true)
    }
    
    private func handleSetSpeakerphoneOn(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let on = args["on"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing on argument", details: nil))
            return
        }
        
        do {
            try audioEngine?.setSpeakerphoneOn(on)
            result(true)
        } catch {
            result(FlutterError(code: "SPEAKER_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    // MARK: - Playback Buffer
    
    private func handleClearPlaybackBuffer(result: @escaping FlutterResult) {
        audioEngine?.clearPlaybackBuffer()
        result(true)
    }
    
    // MARK: - Send Event
    
    private func handleSendEvent(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let eventType = args["eventType"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing eventType argument", details: nil))
            return
        }
        
        let data = args["data"] as? [String: Any]
        webSocketManager?.sendEvent(eventType, data: data)
        result(true)
    }
    
    // MARK: - Audio Info
    
    private func handleGetAudioInfo(result: @escaping FlutterResult) {
        if let info = audioEngine?.getAudioInfo() {
            result(info)
        } else {
            result(nil)
        }
    }
    
    // MARK: - AEC Availability
    
    private func handleCheckAECAvailability(result: @escaping FlutterResult) {
        // VoiceProcessingIO is available on all iOS devices
        result(true)
    }
    
    // MARK: - Server Events
    
    private func handleServerEvent(_ method: String, data: Any?) {
        switch method {
        case "pause":
            isPaused = true
            sendEvent(["type": "agentState", "state": "paused"])
            
        case "unpause":
            isPaused = false
            sendEvent(["type": "agentState", "state": "speaking"])
            
        case "clear":
            isPaused = false
            audioEngine?.clearPlaybackBuffer()
            sendEvent(["type": "agentState", "state": "listening"])
            
        case "ontranscript":
            if let text = data as? String {
                sendEvent(["type": "transcript", "text": text, "speaker": "user", "isFinal": true])
            } else if let dict = data as? [String: Any], let text = dict["text"] as? String {
                let isFinal = dict["is_final"] as? Bool ?? true
                sendEvent(["type": "transcript", "text": text, "speaker": "user", "isFinal": isFinal])
            }
            
        case "onresponsetext":
            if let text = data as? String {
                sendEvent(["type": "transcript", "text": text, "speaker": "agent", "isFinal": true])
            } else if let dict = data as? [String: Any], let text = dict["text"] as? String {
                sendEvent(["type": "transcript", "text": text, "speaker": "agent", "isFinal": true])
            }
            
        case "onsessionended":
            var reason: String? = nil
            var duration: Int? = nil
            if let dict = data as? [String: Any] {
                reason = dict["reason"] as? String
                duration = dict["duration"] as? Int
            }
            sendEvent(["type": "sessionEnded", "reason": reason as Any, "duration": duration as Any])
            
        case "start_answering":
            sendEvent(["type": "agentState", "state": "speaking"])
            
        case "thinking":
            sendEvent(["type": "agentState", "state": "thinking"])
            
        case "onready":
            var sessionId: String? = nil
            if let dict = data as? [String: Any] {
                sessionId = dict["session_id"] as? String
            }
            sendEvent(["type": "ready", "sessionId": sessionId as Any])
            
        default:
            break
        }
    }
    
    // MARK: - Event Sink
    
    private func sendEvent(_ event: [String: Any]) {
        DispatchQueue.main.async {
            self.eventSink?(event)
        }
    }
}

// MARK: - FlutterStreamHandler

extension FlutterAutoEchoCancellationWebsocketPlugin: FlutterStreamHandler {
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
