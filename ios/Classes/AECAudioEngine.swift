import Foundation
import AVFoundation
import AudioToolbox

/// Handles audio capture and playback with AEC via VoiceProcessingIO
class AECAudioEngine {
    
    // MARK: - Properties
    
    private var audioUnit: AudioComponentInstance?
    private var isRunning = false
    private var isMuted = false
    
    // Audio format: 16-bit PCM, 16kHz, Mono
    private let sampleRate: Double
    private let channels: UInt32 = 1
    private let bytesPerSample: UInt32 = 2  // 16-bit
    
    // Callbacks to Dart/Flutter
    var onAudioCaptured: ((Data) -> Void)?
    var onAudioLevel: ((Float, Bool) -> Void)?
    
    // Buffer for incoming audio from server (to be played)
    private var playbackBuffer = CircularBuffer(capacity: 64000)  // ~2 seconds buffer
    private let bufferLock = NSLock()
    
    // Audio level tracking
    private var inputLevel: Float = 0
    private var outputLevel: Float = 0
    
    // Speaker state
    private var isSpeakerMuted = false
    
    // MARK: - Initialization
    
    init(sampleRate: Double = 16000) {
        self.sampleRate = sampleRate
    }
    
    func initialize() throws {
        try setupAudioSession()
        try setupAudioUnit()
    }
    
    // MARK: - Audio Session Setup
    
    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        
        // CRITICAL: Use playAndRecord category with voiceChat mode
        // voiceChat mode enables system-level echo cancellation optimizations
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,  // KEY: Enables AEC optimizations
            options: [
                .defaultToSpeaker,      // Use speaker by default
                .allowBluetooth,        // Support Bluetooth headsets
                .allowBluetoothA2DP
            ]
        )
        
        // Set preferred sample rate
        try session.setPreferredSampleRate(sampleRate)
        
        // Set preferred buffer duration (lower = less latency, more CPU)
        try session.setPreferredIOBufferDuration(0.02)  // 20ms
        
        // Activate the session
        try session.setActive(true)
        
        print("[AECAudioEngine] Audio session configured with sample rate: \(sampleRate)")
    }
    
    // MARK: - VoiceProcessingIO Audio Unit Setup
    
    private func setupAudioUnit() throws {
        // Describe the VoiceProcessingIO Audio Unit
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_VoiceProcessingIO,  // KEY: This enables AEC
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        // Find the component
        guard let component = AudioComponentFindNext(nil, &desc) else {
            throw AECError.componentNotFound
        }
        
        // Create the audio unit instance
        var status = AudioComponentInstanceNew(component, &audioUnit)
        guard status == noErr, let audioUnit = audioUnit else {
            throw AECError.failedToCreateAudioUnit(status)
        }
        
        // Enable input (microphone) on the audio unit
        var enableInput: UInt32 = 1
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,  // Input bus (element 1)
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            throw AECError.failedToEnableInput(status)
        }
        
        // Enable output (speaker) - enabled by default, but be explicit
        var enableOutput: UInt32 = 1
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0,  // Output bus (element 0)
            &enableOutput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            throw AECError.failedToEnableOutput(status)
        }
        
        // Set the audio format for input and output
        var audioFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerSample * channels,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerSample * channels,
            mChannelsPerFrame: channels,
            mBitsPerChannel: bytesPerSample * 8,
            mReserved: 0
        )
        
        // Set format for input scope of output bus (what we send to speaker)
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,  // Output bus
            &audioFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else {
            throw AECError.failedToSetFormat(status)
        }
        
        // Set format for output scope of input bus (what we get from mic)
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,  // Input bus
            &audioFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else {
            throw AECError.failedToSetFormat(status)
        }
        
        // Set up the input callback (microphone capture)
        var inputCallbackStruct = AURenderCallbackStruct(
            inputProc: inputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &inputCallbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status == noErr else {
            throw AECError.failedToSetInputCallback(status)
        }
        
        // Set up the render callback (speaker playback)
        var renderCallbackStruct = AURenderCallbackStruct(
            inputProc: renderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,  // Output bus
            &renderCallbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status == noErr else {
            throw AECError.failedToSetRenderCallback(status)
        }
        
        // Initialize the audio unit
        status = AudioUnitInitialize(audioUnit)
        guard status == noErr else {
            throw AECError.failedToInitialize(status)
        }
        
        print("[AECAudioEngine] VoiceProcessingIO Audio Unit configured")
    }
    
    // MARK: - Start/Stop
    
    func start() throws {
        guard let audioUnit = audioUnit, !isRunning else { return }
        
        let status = AudioOutputUnitStart(audioUnit)
        guard status == noErr else {
            throw AECError.failedToStart(status)
        }
        
        isRunning = true
        print("[AECAudioEngine] Started")
    }
    
    func stop() {
        guard let audioUnit = audioUnit, isRunning else { return }
        
        AudioOutputUnitStop(audioUnit)
        isRunning = false
        print("[AECAudioEngine] Stopped")
    }
    
    // MARK: - Mute Control
    
    func setMicrophoneMuted(_ muted: Bool) {
        isMuted = muted
        print("[AECAudioEngine] Microphone muted: \(muted)")
    }
    
    func setSpeakerMuted(_ muted: Bool) {
        isSpeakerMuted = muted
        print("[AECAudioEngine] Speaker muted: \(muted)")
    }
    
    func setSpeakerphoneOn(_ on: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        if on {
            try session.overrideOutputAudioPort(.speaker)
        } else {
            try session.overrideOutputAudioPort(.none)
        }
        print("[AECAudioEngine] Speakerphone: \(on)")
    }
    
    // MARK: - Playback Buffer Management
    
    /// Add audio data received from server to the playback buffer
    func enqueueAudioForPlayback(_ data: Data) {
        bufferLock.lock()
        playbackBuffer.write(data)
        bufferLock.unlock()
    }
    
    /// Clear the playback buffer (used when interrupted)
    func clearPlaybackBuffer() {
        bufferLock.lock()
        playbackBuffer.clear()
        bufferLock.unlock()
        print("[AECAudioEngine] Playback buffer cleared")
    }
    
    // MARK: - Audio Info
    
    func getAudioInfo() -> [String: Any] {
        return [
            "sampleRate": sampleRate,
            "channels": channels,
            "bytesPerSample": bytesPerSample,
            "isRunning": isRunning,
            "isMuted": isMuted,
            "isSpeakerMuted": isSpeakerMuted,
            "aecEnabled": true,
            "aecType": "VoiceProcessingIO"
        ]
    }
    
    // MARK: - Cleanup
    
    func dispose() {
        stop()
        
        if let audioUnit = audioUnit {
            AudioUnitUninitialize(audioUnit)
            AudioComponentInstanceDispose(audioUnit)
        }
        audioUnit = nil
        
        try? AVAudioSession.sharedInstance().setActive(false)
        print("[AECAudioEngine] Disposed")
    }
    
    // MARK: - Internal Properties Access (for callbacks)
    
    fileprivate var audioUnitInternal: AudioComponentInstance? { audioUnit }
    fileprivate var isMutedInternal: Bool { isMuted }
    fileprivate var isSpeakerMutedInternal: Bool { isSpeakerMuted }
}

// MARK: - Audio Callbacks

/// Input callback: Called when microphone captures audio
private func inputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    
    let engine = Unmanaged<AECAudioEngine>.fromOpaque(inRefCon).takeUnretainedValue()
    
    // Skip if muted
    if engine.isMutedInternal {
        return noErr
    }
    
    // Allocate buffer for captured audio
    var bufferList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: inNumberFrames * 2,  // 16-bit samples
            mData: nil
        )
    )
    
    // Allocate memory for the buffer
    let bufferSize = Int(inNumberFrames * 2)
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
    bufferList.mBuffers.mData = buffer
    
    // Render (capture) the audio from the microphone
    guard let audioUnit = engine.audioUnitInternal else {
        buffer.deallocate()
        return noErr
    }
    
    let status = AudioUnitRender(
        audioUnit,
        ioActionFlags,
        inTimeStamp,
        1,  // Input bus
        inNumberFrames,
        &bufferList
    )
    
    if status == noErr {
        // Convert to Data and send to callback
        let data = Data(bytes: buffer, count: bufferSize)
        
        // Calculate audio level
        let samples = buffer.assumingMemoryBound(to: Int16.self)
        var sum: Float = 0
        for i in 0..<Int(inNumberFrames) {
            let sample = Float(samples[i])
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(inNumberFrames))
        let level = min(1.0, rms / 32768.0 * 10)
        
        // Call the callbacks on main thread
        DispatchQueue.main.async {
            engine.onAudioCaptured?(data)
            engine.onAudioLevel?(level, true)
        }
    }
    
    buffer.deallocate()
    return status
}

/// Render callback: Called when speaker needs audio to play
private func renderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    
    let engine = Unmanaged<AECAudioEngine>.fromOpaque(inRefCon).takeUnretainedValue()
    
    guard let ioData = ioData else { return noErr }
    
    let requiredBytes = Int(inNumberFrames * 2)  // 16-bit samples
    
    // Get the output buffer
    let buffer = ioData.pointee.mBuffers
    guard let outputBuffer = buffer.mData else { return noErr }
    
    // If speaker is muted, output silence
    if engine.isSpeakerMutedInternal {
        memset(outputBuffer, 0, requiredBytes)
        ioData.pointee.mBuffers.mDataByteSize = UInt32(requiredBytes)
        return noErr
    }
    
    // Read from playback buffer
    engine.bufferLock.lock()
    let availableBytes = engine.playbackBuffer.availableBytes
    
    if availableBytes >= requiredBytes {
        // We have enough data - read it
        engine.playbackBuffer.read(into: outputBuffer, count: requiredBytes)
        ioData.pointee.mBuffers.mDataByteSize = UInt32(requiredBytes)
        
        // Calculate audio level
        let samples = outputBuffer.assumingMemoryBound(to: Int16.self)
        var sum: Float = 0
        for i in 0..<Int(inNumberFrames) {
            let sample = Float(samples[i])
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(inNumberFrames))
        let level = min(1.0, rms / 32768.0 * 10)
        
        DispatchQueue.main.async {
            engine.onAudioLevel?(level, false)
        }
    } else {
        // Not enough data - output silence
        memset(outputBuffer, 0, requiredBytes)
        ioData.pointee.mBuffers.mDataByteSize = UInt32(requiredBytes)
    }
    
    engine.bufferLock.unlock()
    
    return noErr
}

// MARK: - Errors

enum AECError: Error, LocalizedError {
    case componentNotFound
    case failedToCreateAudioUnit(OSStatus)
    case failedToEnableInput(OSStatus)
    case failedToEnableOutput(OSStatus)
    case failedToSetFormat(OSStatus)
    case failedToSetInputCallback(OSStatus)
    case failedToSetRenderCallback(OSStatus)
    case failedToInitialize(OSStatus)
    case failedToStart(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .componentNotFound:
            return "VoiceProcessingIO component not found"
        case .failedToCreateAudioUnit(let status):
            return "Failed to create audio unit: \(status)"
        case .failedToEnableInput(let status):
            return "Failed to enable input: \(status)"
        case .failedToEnableOutput(let status):
            return "Failed to enable output: \(status)"
        case .failedToSetFormat(let status):
            return "Failed to set format: \(status)"
        case .failedToSetInputCallback(let status):
            return "Failed to set input callback: \(status)"
        case .failedToSetRenderCallback(let status):
            return "Failed to set render callback: \(status)"
        case .failedToInitialize(let status):
            return "Failed to initialize: \(status)"
        case .failedToStart(let status):
            return "Failed to start: \(status)"
        }
    }
}

// MARK: - Circular Buffer

/// Simple circular buffer for audio data
class CircularBuffer {
    private var buffer: [UInt8]
    private var readIndex = 0
    private var writeIndex = 0
    private var count = 0
    private let capacity: Int
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [UInt8](repeating: 0, count: capacity)
    }
    
    var availableBytes: Int { count }
    
    func write(_ data: Data) {
        for byte in data {
            buffer[writeIndex] = byte
            writeIndex = (writeIndex + 1) % capacity
            
            if count < capacity {
                count += 1
            } else {
                // Overwrite oldest data
                readIndex = (readIndex + 1) % capacity
            }
        }
    }
    
    func read(into destination: UnsafeMutableRawPointer, count bytesToRead: Int) {
        let bytes = destination.assumingMemoryBound(to: UInt8.self)
        
        for i in 0..<min(bytesToRead, count) {
            bytes[i] = buffer[readIndex]
            readIndex = (readIndex + 1) % capacity
        }
        count -= min(bytesToRead, count)
    }
    
    func clear() {
        readIndex = 0
        writeIndex = 0
        count = 0
    }
}
