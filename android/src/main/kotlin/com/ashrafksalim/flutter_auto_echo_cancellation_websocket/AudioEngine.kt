package com.ashrafksalim.flutter_auto_echo_cancellation_websocket

import android.media.*
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.media.audiofx.AutomaticGainControl
import android.os.Build
import android.os.Process
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.concurrent.thread
import kotlin.math.sqrt

/**
 * AudioEngine handles audio capture and playback with native AEC.
 * 
 * Uses AudioRecord with VOICE_COMMUNICATION source and AcousticEchoCanceler
 * to provide echo cancellation. Both input and output share the same audio
 * session ID to enable proper AEC correlation.
 */
class AudioEngine {
    
    companion object {
        const val SAMPLE_RATE = 16000
        const val CHANNEL_CONFIG_IN = AudioFormat.CHANNEL_IN_MONO
        const val CHANNEL_CONFIG_OUT = AudioFormat.CHANNEL_OUT_MONO
        const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
    }
    
    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var acousticEchoCanceler: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var automaticGainControl: AutomaticGainControl? = null
    
    private var isRunning = false
    private var isMuted = false
    private var isSpeakerMuted = false
    private var captureThread: Thread? = null
    private var playbackThread: Thread? = null
    
    // Playback buffer
    private val playbackQueue = ConcurrentLinkedQueue<ByteArray>()
    
    // Configuration
    private var sampleRate: Int = SAMPLE_RATE
    private var enableNoiseSuppression: Boolean = true
    private var enableAutoGainControl: Boolean = true
    
    // Callbacks
    var onAudioCaptured: ((ByteArray) -> Unit)? = null
    var onAudioLevel: ((Float, Boolean) -> Unit)? = null
    var onAECStatus: ((Boolean, Boolean, String?) -> Unit)? = null
    
    // Audio session ID
    private var audioSessionId: Int = 0
    
    /**
     * Initialize the audio engine with optional configuration
     */
    fun initialize(
        sampleRate: Int = SAMPLE_RATE,
        enableNoiseSuppression: Boolean = true,
        enableAutoGainControl: Boolean = true
    ) {
        this.sampleRate = sampleRate
        this.enableNoiseSuppression = enableNoiseSuppression
        this.enableAutoGainControl = enableAutoGainControl
        
        // Create AudioRecord with VOICE_COMMUNICATION source
        // This is KEY for AEC to work properly
        val minBufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            CHANNEL_CONFIG_IN,
            AUDIO_FORMAT
        )
        
        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,  // KEY: Enables AEC
            sampleRate,
            CHANNEL_CONFIG_IN,
            AUDIO_FORMAT,
            minBufferSize * 2
        )
        
        audioSessionId = audioRecord!!.audioSessionId
        
        // Enable Acoustic Echo Canceler if available
        val aecAvailable = AcousticEchoCanceler.isAvailable()
        if (aecAvailable) {
            try {
                acousticEchoCanceler = AcousticEchoCanceler.create(audioSessionId)
                acousticEchoCanceler?.enabled = true
                println("[AudioEngine] AEC enabled (session: $audioSessionId)")
                onAECStatus?.invoke(true, true, "AcousticEchoCanceler")
            } catch (e: Exception) {
                println("[AudioEngine] Failed to create AEC: ${e.message}")
                onAECStatus?.invoke(false, true, null)
            }
        } else {
            println("[AudioEngine] AEC not available on this device")
            onAECStatus?.invoke(false, false, null)
        }
        
        // Enable Noise Suppressor if available and requested
        if (enableNoiseSuppression && NoiseSuppressor.isAvailable()) {
            try {
                noiseSuppressor = NoiseSuppressor.create(audioSessionId)
                noiseSuppressor?.enabled = true
                println("[AudioEngine] Noise suppressor enabled")
            } catch (e: Exception) {
                println("[AudioEngine] Failed to create noise suppressor: ${e.message}")
            }
        }
        
        // Enable Automatic Gain Control if available and requested
        if (enableAutoGainControl && AutomaticGainControl.isAvailable()) {
            try {
                automaticGainControl = AutomaticGainControl.create(audioSessionId)
                automaticGainControl?.enabled = true
                println("[AudioEngine] AGC enabled")
            } catch (e: Exception) {
                println("[AudioEngine] Failed to create AGC: ${e.message}")
            }
        }
        
        // Create AudioTrack with same session ID for AEC correlation
        val playBufferSize = AudioTrack.getMinBufferSize(
            sampleRate,
            CHANNEL_CONFIG_OUT,
            AUDIO_FORMAT
        )
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            
            val audioFormat = AudioFormat.Builder()
                .setSampleRate(sampleRate)
                .setChannelMask(CHANNEL_CONFIG_OUT)
                .setEncoding(AUDIO_FORMAT)
                .build()
            
            audioTrack = AudioTrack(
                audioAttributes,
                audioFormat,
                playBufferSize * 2,
                AudioTrack.MODE_STREAM,
                audioSessionId  // KEY: Same session ID for AEC
            )
        } else {
            @Suppress("DEPRECATION")
            audioTrack = AudioTrack(
                AudioManager.STREAM_VOICE_CALL,
                sampleRate,
                CHANNEL_CONFIG_OUT,
                AUDIO_FORMAT,
                playBufferSize * 2,
                AudioTrack.MODE_STREAM,
                audioSessionId
            )
        }
        
        println("[AudioEngine] Initialized with session ID: $audioSessionId")
    }
    
    /**
     * Start audio capture and playback
     */
    fun start() {
        if (isRunning) return
        isRunning = true
        
        // Start recording
        audioRecord?.startRecording()
        
        // Start playback
        audioTrack?.play()
        
        // Capture thread
        captureThread = thread(name = "AudioCapture") {
            Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
            
            val bufferSize = (sampleRate * 2 * 20) / 1000  // 20ms at sample rate, 16-bit mono
            val buffer = ByteArray(bufferSize)
            
            while (isRunning) {
                if (isMuted) {
                    Thread.sleep(10)
                    continue
                }
                
                val bytesRead = audioRecord?.read(buffer, 0, bufferSize) ?: 0
                
                if (bytesRead > 0) {
                    val audioData = buffer.copyOf(bytesRead)
                    onAudioCaptured?.invoke(audioData)
                    
                    // Calculate audio level
                    val level = calculateAudioLevel(audioData)
                    onAudioLevel?.invoke(level, true)
                }
            }
        }
        
        // Playback thread
        playbackThread = thread(name = "AudioPlayback") {
            Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
            
            while (isRunning) {
                val data = playbackQueue.poll()
                if (data != null && !isSpeakerMuted) {
                    audioTrack?.write(data, 0, data.size)
                    
                    // Calculate audio level
                    val level = calculateAudioLevel(data)
                    onAudioLevel?.invoke(level, false)
                } else {
                    Thread.sleep(5)
                }
            }
        }
        
        println("[AudioEngine] Started")
    }
    
    /**
     * Stop audio capture and playback
     */
    fun stop() {
        isRunning = false
        
        captureThread?.join(1000)
        playbackThread?.join(1000)
        
        audioRecord?.stop()
        audioTrack?.stop()
        
        println("[AudioEngine] Stopped")
    }
    
    /**
     * Mute/unmute microphone
     */
    fun setMicrophoneMuted(muted: Boolean) {
        isMuted = muted
        println("[AudioEngine] Microphone muted: $muted")
    }
    
    /**
     * Mute/unmute speaker
     */
    fun setSpeakerMuted(muted: Boolean) {
        isSpeakerMuted = muted
        println("[AudioEngine] Speaker muted: $muted")
    }
    
    /**
     * Enqueue audio data for playback
     */
    fun enqueueAudioForPlayback(data: ByteArray) {
        playbackQueue.offer(data)
    }
    
    /**
     * Clear the playback buffer
     */
    fun clearPlaybackBuffer() {
        playbackQueue.clear()
        println("[AudioEngine] Playback buffer cleared")
    }
    
    /**
     * Get audio info
     */
    fun getAudioInfo(): Map<String, Any> {
        return mapOf(
            "sampleRate" to sampleRate,
            "channels" to 1,
            "bytesPerSample" to 2,
            "isRunning" to isRunning,
            "isMuted" to isMuted,
            "isSpeakerMuted" to isSpeakerMuted,
            "audioSessionId" to audioSessionId,
            "aecEnabled" to (acousticEchoCanceler?.enabled ?: false),
            "aecAvailable" to AcousticEchoCanceler.isAvailable(),
            "nsEnabled" to (noiseSuppressor?.enabled ?: false),
            "agcEnabled" to (automaticGainControl?.enabled ?: false)
        )
    }
    
    /**
     * Check if AEC is available
     */
    fun isAECAvailable(): Boolean {
        return AcousticEchoCanceler.isAvailable()
    }
    
    /**
     * Release all resources
     */
    fun dispose() {
        stop()
        
        acousticEchoCanceler?.release()
        noiseSuppressor?.release()
        automaticGainControl?.release()
        audioRecord?.release()
        audioTrack?.release()
        
        acousticEchoCanceler = null
        noiseSuppressor = null
        automaticGainControl = null
        audioRecord = null
        audioTrack = null
        
        println("[AudioEngine] Disposed")
    }
    
    /**
     * Calculate audio level from PCM data
     */
    private fun calculateAudioLevel(data: ByteArray): Float {
        var sum = 0.0
        val samples = data.size / 2
        
        for (i in 0 until samples) {
            val sample = ((data[i * 2 + 1].toInt() shl 8) or (data[i * 2].toInt() and 0xFF)).toShort()
            sum += sample.toDouble() * sample.toDouble()
        }
        
        val rms = sqrt(sum / samples)
        return (rms / 32768.0 * 10).toFloat().coerceIn(0f, 1f)
    }
}
