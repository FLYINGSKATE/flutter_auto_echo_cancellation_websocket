package com.ashrafksalim.flutter_auto_echo_cancellation_websocket

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Flutter plugin for real-time voice communication with automatic echo cancellation.
 * 
 * This plugin provides native AEC using Android's AcousticEchoCanceler and
 * WebSocket-based audio streaming for voice agent applications.
 * 
 * @author Ashraf K Salim
 * @email ashrafk.salim@gmail.com
 * @github https://github.com/FLYINGSKATE
 */
class FlutterAutoEchoCancellationWebsocketPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, 
    EventChannel.StreamHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
    
    companion object {
        private const val PERMISSION_REQUEST_CODE = 1001
    }
    
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    
    private var audioEngine: AudioEngine? = null
    private var webSocketManager: WebSocketManager? = null
    private var isPaused = false
    
    private var context: Context? = null
    private var activity: Activity? = null
    
    // Pending connection after permission granted
    private var pendingConnectionArgs: Map<String, Any>? = null
    private var pendingResult: MethodChannel.Result? = null
    
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        
        methodChannel = MethodChannel(binding.binaryMessenger, "flutter_auto_echo_cancellation_websocket")
        methodChannel.setMethodCallHandler(this)
        
        eventChannel = EventChannel(binding.binaryMessenger, "flutter_auto_echo_cancellation_websocket/events")
        eventChannel.setStreamHandler(this)
    }
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        context = null
    }
    
    // ActivityAware implementation
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }
    
    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }
    
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }
    
    override fun onDetachedFromActivity() {
        activity = null
    }
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "connect" -> handleConnect(call, result)
            "disconnect" -> handleDisconnect(result)
            "setMicrophoneMuted" -> handleSetMicrophoneMuted(call, result)
            "setSpeakerMuted" -> handleSetSpeakerMuted(call, result)
            "setSpeakerphoneOn" -> handleSetSpeakerphoneOn(call, result)
            "clearPlaybackBuffer" -> handleClearPlaybackBuffer(result)
            "sendEvent" -> handleSendEvent(call, result)
            "getAudioInfo" -> handleGetAudioInfo(result)
            "checkAECAvailability" -> handleCheckAECAvailability(result)
            else -> result.notImplemented()
        }
    }
    
    private fun handleConnect(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<String, Any>
        if (args == null) {
            result.error("INVALID_ARGS", "Missing arguments", null)
            return
        }
        
        val endpoint = args["endpoint"] as? String
        val agentId = args["agentId"] as? String
        val publicKey = args["publicKey"] as? String
        
        if (endpoint == null || agentId == null || publicKey == null) {
            result.error("INVALID_ARGS", "Missing required arguments (endpoint, agentId, publicKey)", null)
            return
        }
        
        // Check for audio permission
        val ctx = context ?: run {
            result.error("NO_CONTEXT", "Context not available", null)
            return
        }
        
        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) 
            != PackageManager.PERMISSION_GRANTED) {
            // Request permission
            val act = activity
            if (act != null) {
                pendingConnectionArgs = args
                pendingResult = result
                ActivityCompat.requestPermissions(
                    act,
                    arrayOf(Manifest.permission.RECORD_AUDIO),
                    PERMISSION_REQUEST_CODE
                )
            } else {
                result.error("PERMISSION_DENIED", "Microphone permission not granted and no activity available", null)
            }
            return
        }
        
        // Permission granted, proceed with connection
        performConnect(args, result)
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode == PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                // Permission granted, proceed with pending connection
                val args = pendingConnectionArgs
                val result = pendingResult
                if (args != null && result != null) {
                    performConnect(args, result)
                }
            } else {
                pendingResult?.error("PERMISSION_DENIED", "Microphone permission denied", null)
            }
            pendingConnectionArgs = null
            pendingResult = null
            return true
        }
        return false
    }
    
    @Suppress("UNCHECKED_CAST")
    private fun performConnect(args: Map<String, Any>, result: MethodChannel.Result) {
        try {
            val endpoint = args["endpoint"] as String
            val agentId = args["agentId"] as String
            val publicKey = args["publicKey"] as String
            val metadata = args["metadata"] as? Map<String, Any>
            val includeMetadataInPrompt = args["includeMetadataInPrompt"] as? Boolean ?: true
            val sampleRate = (args["sampleRate"] as? Number)?.toInt() ?: 16000
            val enableNoiseSuppression = args["enableNoiseSuppression"] as? Boolean ?: true
            val enableAutoGainControl = args["enableAutoGainControl"] as? Boolean ?: true
            val autoReconnect = args["autoReconnect"] as? Boolean ?: true
            val maxReconnectAttempts = (args["maxReconnectAttempts"] as? Number)?.toInt() ?: 3
            val reconnectDelayMs = (args["reconnectDelayMs"] as? Number)?.toInt() ?: 1000
            
            // Initialize audio engine
            audioEngine = AudioEngine()
            audioEngine?.initialize(
                sampleRate = sampleRate,
                enableNoiseSuppression = enableNoiseSuppression,
                enableAutoGainControl = enableAutoGainControl
            )
            
            audioEngine?.onAudioCaptured = { data ->
                webSocketManager?.sendAudio(data)
            }
            
            audioEngine?.onAudioLevel = { level, isInput ->
                sendEvent(mapOf(
                    "type" to "audioLevel",
                    "level" to level,
                    "isInput" to isInput
                ))
            }
            
            audioEngine?.onAECStatus = { isEnabled, isSupported, aecType ->
                sendEvent(mapOf(
                    "type" to "aecStatus",
                    "isEnabled" to isEnabled,
                    "isSupported" to isSupported,
                    "aecType" to aecType
                ))
            }
            
            // Initialize WebSocket
            webSocketManager = WebSocketManager()
            
            webSocketManager?.onConnected = {
                sendEvent(mapOf("type" to "connected"))
            }
            
            webSocketManager?.onDisconnected = { reason ->
                audioEngine?.stop()
                sendEvent(mapOf("type" to "disconnected", "reason" to reason))
            }
            
            webSocketManager?.onAudioReceived = { data ->
                if (!isPaused) {
                    audioEngine?.enqueueAudioForPlayback(data)
                }
            }
            
            webSocketManager?.onError = { code, message, isFatal ->
                sendEvent(mapOf(
                    "type" to "error",
                    "code" to code,
                    "message" to message,
                    "isFatal" to isFatal
                ))
            }
            
            webSocketManager?.onEvent = { method, data ->
                handleServerEvent(method, data)
            }
            
            // Connect
            webSocketManager?.connect(
                endpoint = endpoint,
                agentId = agentId,
                publicKey = publicKey,
                metadata = metadata,
                includeMetadataInPrompt = includeMetadataInPrompt,
                autoReconnect = autoReconnect,
                maxReconnectAttempts = maxReconnectAttempts,
                reconnectDelayMs = reconnectDelayMs
            )
            
            // Start audio
            audioEngine?.start()
            
            result.success(true)
            
        } catch (e: Exception) {
            result.error("INIT_ERROR", e.message, null)
        }
    }
    
    private fun handleDisconnect(result: MethodChannel.Result) {
        webSocketManager?.disconnect()
        audioEngine?.stop()
        audioEngine?.dispose()
        
        webSocketManager = null
        audioEngine = null
        isPaused = false
        
        result.success(true)
    }
    
    private fun handleSetMicrophoneMuted(call: MethodCall, result: MethodChannel.Result) {
        val muted = call.argument<Boolean>("muted")
        if (muted == null) {
            result.error("INVALID_ARGS", "Missing muted argument", null)
            return
        }
        
        audioEngine?.setMicrophoneMuted(muted)
        result.success(true)
    }
    
    private fun handleSetSpeakerMuted(call: MethodCall, result: MethodChannel.Result) {
        val muted = call.argument<Boolean>("muted")
        if (muted == null) {
            result.error("INVALID_ARGS", "Missing muted argument", null)
            return
        }
        
        audioEngine?.setSpeakerMuted(muted)
        result.success(true)
    }
    
    private fun handleSetSpeakerphoneOn(call: MethodCall, result: MethodChannel.Result) {
        val on = call.argument<Boolean>("on")
        if (on == null) {
            result.error("INVALID_ARGS", "Missing on argument", null)
            return
        }
        
        val ctx = context ?: run {
            result.error("NO_CONTEXT", "Context not available", null)
            return
        }
        
        val audioManager = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.isSpeakerphoneOn = on
        result.success(true)
    }
    
    private fun handleClearPlaybackBuffer(result: MethodChannel.Result) {
        audioEngine?.clearPlaybackBuffer()
        result.success(true)
    }
    
    @Suppress("UNCHECKED_CAST")
    private fun handleSendEvent(call: MethodCall, result: MethodChannel.Result) {
        val eventType = call.argument<String>("eventType")
        if (eventType == null) {
            result.error("INVALID_ARGS", "Missing eventType argument", null)
            return
        }
        
        val data = call.argument<Map<String, Any>>("data")
        webSocketManager?.sendEvent(eventType, data)
        result.success(true)
    }
    
    private fun handleGetAudioInfo(result: MethodChannel.Result) {
        val info = audioEngine?.getAudioInfo()
        result.success(info)
    }
    
    private fun handleCheckAECAvailability(result: MethodChannel.Result) {
        val available = audioEngine?.isAECAvailable() 
            ?: android.media.audiofx.AcousticEchoCanceler.isAvailable()
        result.success(available)
    }
    
    private fun handleServerEvent(method: String, data: Any?) {
        when (method) {
            "pause" -> {
                isPaused = true
                sendEvent(mapOf("type" to "agentState", "state" to "paused"))
            }
            "unpause" -> {
                isPaused = false
                sendEvent(mapOf("type" to "agentState", "state" to "speaking"))
            }
            "clear" -> {
                isPaused = false
                audioEngine?.clearPlaybackBuffer()
                sendEvent(mapOf("type" to "agentState", "state" to "listening"))
            }
            "ontranscript" -> {
                val text = when (data) {
                    is String -> data
                    is org.json.JSONObject -> data.optString("text")
                    else -> null
                }
                val isFinal = when (data) {
                    is org.json.JSONObject -> data.optBoolean("is_final", true)
                    else -> true
                }
                if (text != null) {
                    sendEvent(mapOf(
                        "type" to "transcript",
                        "text" to text,
                        "speaker" to "user",
                        "isFinal" to isFinal
                    ))
                }
            }
            "onresponsetext" -> {
                val text = when (data) {
                    is String -> data
                    is org.json.JSONObject -> data.optString("text")
                    else -> null
                }
                if (text != null) {
                    sendEvent(mapOf(
                        "type" to "transcript",
                        "text" to text,
                        "speaker" to "agent",
                        "isFinal" to true
                    ))
                }
            }
            "onsessionended" -> {
                val reason = when (data) {
                    is org.json.JSONObject -> data.optString("reason")
                    else -> null
                }
                val duration = when (data) {
                    is org.json.JSONObject -> data.optInt("duration", 0)
                    else -> 0
                }
                sendEvent(mapOf(
                    "type" to "sessionEnded",
                    "reason" to reason,
                    "duration" to duration
                ))
            }
            "start_answering" -> {
                sendEvent(mapOf("type" to "agentState", "state" to "speaking"))
            }
            "thinking" -> {
                sendEvent(mapOf("type" to "agentState", "state" to "thinking"))
            }
            "onready" -> {
                val sessionId = when (data) {
                    is org.json.JSONObject -> data.optString("session_id")
                    else -> null
                }
                sendEvent(mapOf("type" to "ready", "sessionId" to sessionId))
            }
        }
    }
    
    private fun sendEvent(event: Map<String, Any?>) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            eventSink?.success(event)
        }
    }
    
    // StreamHandler implementation
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }
    
    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
