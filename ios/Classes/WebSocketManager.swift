import Foundation

/// Manages WebSocket connection to voice server
class WebSocketManager: NSObject {
    
    // MARK: - Properties
    
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    private var pingTimer: Timer?
    private var packetCount = 0
    
    // Configuration
    private var endpoint: String = ""
    
    // Callbacks
    var onConnected: (() -> Void)?
    var onDisconnected: ((String?) -> Void)?
    var onAudioReceived: ((Data) -> Void)?
    var onError: ((String, String, Bool) -> Void)?  // code, message, isFatal
    var onEvent: ((String, Any?) -> Void)?  // method, data
    
    // Connection params for reconnection
    private var pendingAgentId: String?
    private var pendingPublicKey: String?
    private var pendingMetadata: [String: Any]?
    private var pendingIncludeMetadataInPrompt: Bool = true
    
    // Reconnection
    private var autoReconnect: Bool = true
    private var maxReconnectAttempts: Int = 3
    private var reconnectDelayMs: Int = 1000
    private var reconnectAttempts: Int = 0
    
    // MARK: - Connection
    
    func connect(
        endpoint: String,
        agentId: String,
        publicKey: String,
        metadata: [String: Any]?,
        includeMetadataInPrompt: Bool,
        autoReconnect: Bool = true,
        maxReconnectAttempts: Int = 3,
        reconnectDelayMs: Int = 1000
    ) {
        self.endpoint = endpoint
        self.pendingAgentId = agentId
        self.pendingPublicKey = publicKey
        self.pendingMetadata = metadata
        self.pendingIncludeMetadataInPrompt = includeMetadataInPrompt
        self.autoReconnect = autoReconnect
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectDelayMs = reconnectDelayMs
        self.reconnectAttempts = 0
        
        performConnect()
    }
    
    private func performConnect() {
        guard let url = URL(string: endpoint) else {
            onError?("INVALID_URL", "Invalid WebSocket URL: \(endpoint)", true)
            return
        }
        
        // Create URL session
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        
        // Create WebSocket task
        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()
        
        print("[WebSocket] Connecting to \(endpoint)")
    }
    
    private func sendInitiateMessage() {
        guard let agentId = pendingAgentId,
              let publicKey = pendingPublicKey else {
            return
        }
        
        var initiateData: [String: Any] = [
            "agent": ["agent_id": agentId],
            "public_key": publicKey,
            "include_metadata_in_prompt": pendingIncludeMetadataInPrompt
        ]
        
        if let metadata = pendingMetadata {
            initiateData["metadata"] = metadata
        }
        
        let message: [String: Any] = [
            "method": "initiate",
            "data": initiateData
        ]
        
        sendJSON(message)
        print("[WebSocket] Sent initiate message with metadata: \(pendingMetadata ?? [:])")
    }
    
    func disconnect() {
        autoReconnect = false
        pingTimer?.invalidate()
        pingTimer = nil
        
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
        
        onDisconnected?("User disconnected")
        print("[WebSocket] Disconnected")
    }
    
    // MARK: - Send Audio
    
    func sendAudio(_ data: Data) {
        guard isConnected else { return }
        
        // Send as binary message
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocket?.send(message) { [weak self] error in
            if let error = error {
                self?.onError?("SEND_AUDIO_ERROR", "Send audio error: \(error.localizedDescription)", false)
            }
        }
        
        // Send ping every 1000 packets to keep connection alive
        packetCount += 1
        if packetCount >= 1000 {
            sendPing()
            packetCount = 0
        }
    }
    
    // MARK: - Send Custom Event
    
    func sendEvent(_ eventType: String, data: [String: Any]?) {
        var message: [String: Any] = ["method": eventType]
        if let data = data {
            message["data"] = data
        }
        sendJSON(message)
    }
    
    // MARK: - Send JSON
    
    private func sendJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        
        let message = URLSessionWebSocketTask.Message.string(string)
        webSocket?.send(message) { [weak self] error in
            if let error = error {
                self?.onError?("SEND_JSON_ERROR", "Send JSON error: \(error.localizedDescription)", false)
            }
        }
    }
    
    private func sendPing() {
        sendJSON(["method": "ping"])
    }
    
    // MARK: - Receive Messages
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                // Continue receiving
                self?.receiveMessage()
                
            case .failure(let error):
                self?.handleReceiveError(error)
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            // Binary data = audio from agent
            onAudioReceived?(data)
            
        case .string(let string):
            // JSON event
            handleJSONMessage(string)
            
        @unknown default:
            break
        }
    }
    
    private func handleJSONMessage(_ string: String) {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String else {
            return
        }
        
        let eventData = json["data"]
        
        switch method {
        case "onready":
            print("[WebSocket] Ready - session started")
            onEvent?("onready", eventData)
            
        case "pause":
            // Agent paused - buffer audio but don't play
            onEvent?("pause", nil)
            
        case "unpause":
            // Agent resumed - continue playing buffered audio
            onEvent?("unpause", nil)
            
        case "clear":
            // User interrupted - clear audio buffer
            onEvent?("clear", nil)
            
        case "ontranscript":
            // User's speech transcript
            onEvent?("ontranscript", eventData)
            
        case "onresponsetext":
            // Agent's response transcript
            onEvent?("onresponsetext", eventData)
            
        case "onsessionended":
            // Session ended
            onEvent?("onsessionended", eventData)
            disconnect()
            
        case "start_answering":
            // Agent started responding
            onEvent?("start_answering", nil)
            
        case "thinking":
            // Agent is thinking
            onEvent?("thinking", nil)
            
        case "pong":
            // Pong response - ignore
            break
            
        default:
            print("[WebSocket] Unknown event: \(method)")
            onEvent?(method, eventData)
        }
    }
    
    private func handleReceiveError(_ error: Error) {
        let nsError = error as NSError
        
        // Check if it's a cancellation (normal disconnect)
        if nsError.code == 57 || nsError.code == 54 {
            // Connection closed
            handleDisconnect(reason: "Connection closed")
            return
        }
        
        onError?("RECEIVE_ERROR", "Receive error: \(error.localizedDescription)", false)
        handleDisconnect(reason: error.localizedDescription)
    }
    
    private func handleDisconnect(reason: String?) {
        isConnected = false
        
        // Try to reconnect if enabled
        if autoReconnect && reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            print("[WebSocket] Attempting reconnection \(reconnectAttempts)/\(maxReconnectAttempts)")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(reconnectDelayMs)) { [weak self] in
                self?.performConnect()
            }
        } else {
            onDisconnected?(reason)
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketManager: URLSessionWebSocketDelegate {
    
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        isConnected = true
        reconnectAttempts = 0
        print("[WebSocket] Connected")
        
        // Send initiate message
        sendInitiateMessage()
        
        // Start receiving messages
        receiveMessage()
        
        onConnected?()
    }
    
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        isConnected = false
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) }
        print("[WebSocket] Closed with code: \(closeCode), reason: \(reasonString ?? "none")")
        handleDisconnect(reason: reasonString)
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            print("[WebSocket] Task completed with error: \(error)")
            handleDisconnect(reason: error.localizedDescription)
        }
    }
}
