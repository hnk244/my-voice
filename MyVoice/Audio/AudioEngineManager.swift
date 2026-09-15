import AVFoundation
import Combine

/// Central audio engine manager.
///
/// Audio graph:
/// ```
///  AVAudioInputNode (mic)
///       │
///       ▼
///   micMixerNode  ←── GainProcessor
///       │
///       ▼
///  mainMixerNode  ◄── musicMixerNode ◄── playerNode (AVAudioPlayerNode)
///       │
///       ▼
///  outputNode (AVAudioEngine built-in)
/// ```
final class AudioEngineManager: ObservableObject {

    // MARK: - Published

    @Published var state: AudioEngineState = .idle
    @Published var micPeakLevel: Float = 0
    @Published var musicPeakLevel: Float = 0

    // MARK: - Audio Graph Nodes

    private let engine = AVAudioEngine()
    private let micMixerNode = AVAudioMixerNode()
    private let musicMixerNode = AVAudioMixerNode()
    private let playerNode = AVAudioPlayerNode()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 3)
    private let reverbNode = AVAudioUnitReverb()

    // MARK: - Supporting Managers

    private let sessionManager = AudioSessionManager()
    private let recorder = AudioRecorder()

    // MARK: - State

    private var musicFile: AVAudioFile?
    private var meteringTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    /// Request permission and start the audio engine.
    func activate() async throws {
        guard state == .idle else { return }
        state = .starting

        let granted = await sessionManager.requestMicrophonePermission()
        guard granted else {
            state = .idle
            throw AudioSessionManager.SessionError.microphonePermissionDenied
        }

        try sessionManager.activate()

        do {
            try buildGraph()
            try engine.start()
            state = .active
            startMetering()
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    func deactivate() {
        guard state == .active || state == .starting else { return }
        state = .stopping
        stopMetering()
        playerNode.stop()
        engine.stop()
        sessionManager.deactivate()
        state = .idle
    }

    // MARK: - Volume Controls

    func setMicrophoneVolume(_ value: Float) {
        micMixerNode.outputVolume = value
    }

    func setMusicVolume(_ value: Float) {
        musicMixerNode.outputVolume = value
    }

    func setMasterVolume(_ value: Float) {
        engine.mainMixerNode.outputVolume = value
    }

    // MARK: - Music Playback

    func loadMusic(url: URL) throws {
        musicFile = try AVAudioFile(forReading: url)
    }

    func playMusic() {
        guard let file = musicFile else { return }
        playerNode.scheduleFile(file, at: nil, completionHandler: nil)
        playerNode.play()
    }

    func pauseMusic() {
        playerNode.pause()
    }

    func stopMusic() {
        playerNode.stop()
    }

    // MARK: - Recording

    func startRecording(to url: URL) throws {
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        try recorder.start(url: url, format: format)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.recorder.write(buffer: buffer)
        }
    }

    func stopRecording() {
        engine.mainMixerNode.removeTap(onBus: 0)
        recorder.stop()
    }

    // MARK: - Interruption / Route Handling

    func handleInterruption(type: AVAudioSession.InterruptionType) {
        switch type {
        case .began:
            let reason: InterruptionReason = .unknown
            state = .interrupted(reason: reason)
            stopMetering()
        case .ended:
            Task {
                try? await resume()
            }
        @unknown default:
            break
        }
    }

    func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
        switch reason {
        case .oldDeviceUnavailable:
            // e.g., headphones unplugged — pause to avoid speaker bleed
            if state == .active {
                playerNode.pause()
            }
        default:
            break
        }
    }

    func handleMediaServicesReset() {
        // Full tear-down and rebuild after media services crash
        engine.stop()
        state = .idle
        Task {
            try? await activate()
        }
    }

    // MARK: - Diagnostics

    var diagnostics: AudioSessionDiagnostics {
        sessionManager.diagnostics
    }

    var engineCPULoad: Float {
        engine.manualRenderingMaximumFrameCount > 0 ? 0 : engine.outputNode.auAudioUnit.cpuLoad
    }

    // MARK: - Private

    private func buildGraph() throws {
        let inputNode = engine.inputNode
        let mainMixer = engine.mainMixerNode
        let outputNode = engine.outputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Configure reverb
        reverbNode.loadFactoryPreset(.smallRoom)
        reverbNode.wetDryMix = 0 // off by default

        // Attach nodes
        engine.attach(micMixerNode)
        engine.attach(musicMixerNode)
        engine.attach(playerNode)
        engine.attach(eqNode)
        engine.attach(reverbNode)

        // Microphone path: inputNode → micMixer → reverb → eq → mainMixer
        engine.connect(inputNode, to: micMixerNode, format: inputFormat)
        engine.connect(micMixerNode, to: reverbNode, format: inputFormat)
        engine.connect(reverbNode, to: eqNode, format: inputFormat)
        engine.connect(eqNode, to: mainMixer, format: inputFormat)

        // Music path: playerNode → musicMixer → mainMixer
        let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate, channels: 2)
        engine.connect(playerNode, to: musicMixerNode, format: stereoFormat)
        engine.connect(musicMixerNode, to: mainMixer, format: stereoFormat)

        engine.connect(mainMixer, to: outputNode, format: mainMixer.outputFormat(forBus: 0))

        engine.prepare()
    }

    private func resume() async throws {
        guard case .interrupted = state else { return }
        try sessionManager.activate()
        try engine.start()
        state = .active
        startMetering()
    }

    // MARK: - Metering (~15 FPS, battery-friendly)

    private func startMetering() {
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: engine.inputNode.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.updateMicLevel(buffer: buffer)
        }

        meteringTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            self?.updateMusicLevel()
        }
    }

    private func stopMetering() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        if engine.inputNode.numberOfInputs > 0 {
            engine.inputNode.removeTap(onBus: 0)
        }
        micPeakLevel = 0
        musicPeakLevel = 0
    }

    private func updateMicLevel(buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        var peak: Float = 0
        for i in 0..<frameCount {
            let abs = abs(data[i])
            if abs > peak { peak = abs }
        }
        DispatchQueue.main.async { self.micPeakLevel = peak }
    }

    private func updateMusicLevel() {
        // Approximate level from playerNode — real impl would use a tap
        let level = playerNode.isPlaying ? musicMixerNode.outputVolume * 0.7 : 0
        DispatchQueue.main.async { self.musicPeakLevel = level }
    }
}
