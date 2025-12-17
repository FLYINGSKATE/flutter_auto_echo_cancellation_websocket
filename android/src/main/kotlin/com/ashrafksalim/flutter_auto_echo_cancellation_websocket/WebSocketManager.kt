package com.ashrafksalim.flutter_auto_echo_cancellation_websocket

import okhttp3.*
import okio.ByteString
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * WebSocketManager handles WebSocket connection to the voice server.
 * 
 * Supports binary audio data streaming and JSON event handling.
 */
class WebSocketManager {
    
    private var webSocket: WebSocket? = null
    private var client: OkHttpClient? = null
    private var packetCount = 0
    
    // Callbacks
    var onConnected: (() -> Unit)? = null
    var onDisconnected: ((String?) -> Unit)? = null
    var onAudioReceived: ((ByteArray) -> Unit)? = null
    var onError: ((String, String, Boolean) -> Unit)? = null  // code, message, isFatal
    var onEvent: ((String, Any?) -> Unit)? = null
    
    // Connection params for reconnection
    private var pendingEndpoint: String? = null
    private var pendingAgentId: String? = null
    private var pendingPublicKey: String? = null
    private var pendingMetadata: Map<String, Any>? = null
    private var pendingIncludeMetadata: Boolean = true
    
    // Reconnection config
    private var autoReconnect: Boolean = true
    private var maxReconnectAttempts: Int = 3
    private var reconnectDelayMs: Int = 1000
    private var reconnectAttempts: Int = 0
    
    private var isConnected = false
    
    /**
     * Connect to the WebSocket server
     */
    fun connect(
        endpoint: String,
        agentId: String,
        publicKey: String,
        metadata: Map<String, Any>?,
        includeMetadataInPrompt: Boolean,
        autoReconnect: Boolean = true,
        maxReconnectAttempts: Int = 3,
        reconnectDelayMs: Int = 1000
    ) {
        pendingEndpoint = endpoint
        pendingAgentId = agentId
        pendingPublicKey = publicKey
        pendingMetadata = metadata
        pendingIncludeMetadata = includeMetadataInPrompt
        this.autoReconnect = autoReconnect
        this.maxReconnectAttempts = maxReconnectAttempts
        this.reconnectDelayMs = reconnectDelayMs
        this.reconnectAttempts = 0
        
        performConnect()
    }
    
    private fun performConnect() {
        val endpoint = pendingEndpoint ?: return
        
        client = OkHttpClient.Builder()
            .pingInterval(30, TimeUnit.SECONDS)
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()
        
        val request = Request.Builder()
            .url(endpoint)
            .build()
        
        webSocket = client?.newWebSocket(request, object : WebSocketListener() {
            
            override fun onOpen(webSocket: WebSocket, response: Response) {
                println("[WebSocket] Connected")
                isConnected = true
                reconnectAttempts = 0
                sendInitiateMessage()
                onConnected?.invoke()
            }
            
            override fun onMessage(webSocket: WebSocket, text: String) {
                handleJsonMessage(text)
            }
            
            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                onAudioReceived?.invoke(bytes.toByteArray())
            }
            
            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                println("[WebSocket] Closing: $code $reason")
            }
            
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                println("[WebSocket] Closed: $code $reason")
                handleDisconnect(reason)
            }
            
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                println("[WebSocket] Error: ${t.message}")
                onError?.invoke("CONNECTION_ERROR", t.message ?: "Unknown error", true)
                handleDisconnect(t.message)
            }
        })
        
        println("[WebSocket] Connecting to $endpoint")
    }
    
    private fun sendInitiateMessage() {
        val agent = JSONObject().put("agent_id", pendingAgentId)
        
        val data = JSONObject()
            .put("agent", agent)
            .put("public_key", pendingPublicKey)
            .put("include_metadata_in_prompt", pendingIncludeMetadata)
        
        pendingMetadata?.let { metadata ->
            val metadataJson = JSONObject(metadata)
            data.put("metadata", metadataJson)
        }
        
        val message = JSONObject()
            .put("method", "initiate")
            .put("data", data)
        
        webSocket?.send(message.toString())
        println("[WebSocket] Sent initiate message")
    }
    
    /**
     * Send audio data to the server
     */
    fun sendAudio(data: ByteArray) {
        if (!isConnected) return
        
        webSocket?.send(ByteString.of(*data))
        
        packetCount++
        if (packetCount >= 1000) {
            sendPing()
            packetCount = 0
        }
    }
    
    /**
     * Send a custom event to the server
     */
    fun sendEvent(eventType: String, data: Map<String, Any>?) {
        val message = JSONObject().put("method", eventType)
        data?.let {
            message.put("data", JSONObject(it))
        }
        webSocket?.send(message.toString())
    }
    
    private fun sendPing() {
        val message = JSONObject().put("method", "ping")
        webSocket?.send(message.toString())
    }
    
    private fun handleJsonMessage(text: String) {
        try {
            val json = JSONObject(text)
            val method = json.optString("method")
            val data = json.opt("data")
            
            when (method) {
                "pong" -> { /* Ignore pong responses */ }
                else -> onEvent?.invoke(method, data)
            }
            
        } catch (e: Exception) {
            println("[WebSocket] Failed to parse message: $text")
        }
    }
    
    private fun handleDisconnect(reason: String?) {
        isConnected = false
        
        // Try to reconnect if enabled
        if (autoReconnect && reconnectAttempts < maxReconnectAttempts) {
            reconnectAttempts++
            println("[WebSocket] Attempting reconnection $reconnectAttempts/$maxReconnectAttempts")
            
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                performConnect()
            }, reconnectDelayMs.toLong())
        } else {
            onDisconnected?.invoke(reason)
        }
    }
    
    /**
     * Disconnect from the server
     */
    fun disconnect() {
        autoReconnect = false
        isConnected = false
        
        webSocket?.close(1000, "User disconnected")
        webSocket = null
        client?.dispatcher?.executorService?.shutdown()
        client = null
        
        println("[WebSocket] Disconnected")
    }
}
