import AVFoundation
import Combine

/// Central audio engine manager.
///
/// Audio graph:
/// ```
///  AVAudioInputNode (mic)
///       │
///       ▼
///   micMixerNode  ← tap for mic level metering
///       │
///       ▼
///   reverbNode (AVAudioUnitReverb)
///       │
///       ▼
///   eqNode (AVAudioUnitEQ 3-band)
///       │
///       ▼
///  mainMixerNode  ◄── musicMixerNode ← tap for music level metering
///       │                    ▲
///       ▼              playerNode (AVAudioPlayerNode)
///  outputNode (built-in, auto-connected by AVAudioEngine)
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
    /// Dedicated mic gain stage (1 band bypassed; only globalGain applies for 4× boost).
    private let micGainNode = AVAudioUnitEQ(numberOfBands: 1)

    // MARK: - Supporting Managers

    private let sessionManager = AudioSessionManager()
    private let recorder = AudioRecorder()
    private let configurationLock = NSLock()

    // MARK: - State

    private var musicFile: AVAudioFile?
    private var isMicTapInstalled = false
    private var isMusicTapInstalled = false
    private var isGraphBuilt = false       // graph persists across stop/start
    private var noiseCancellationEnabled = false
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    /// Request permission and start the audio engine.
    func activate() async throws {
        guard state == .idle else { return }
        state = .starting

        do {
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                state = .idle
                throw AudioSessionManager.SessionError.microphonePermissionDenied
            }

            try sessionManager.activate(noiseCancellationEnabled: currentNoiseCancellationEnabled())

            // Build the graph only once; it persists across stop/start cycles.
            // Re-attaching or re-connecting nodes that are already in the graph
            // causes AVAudioEngine to throw on the second activation.
            if !isGraphBuilt {
                try buildGraph()
                isGraphBuilt = true
            }

            try engine.start()
            state = .active
            installMeteringTaps()
        } catch {
            state = .idle
            throw error
        }
    }

    func deactivate() {
        guard state != .idle && state != .stopping else { return }
        state = .stopping
        removeMeteringTaps()
        playerNode.stop()
        engine.stop()
        // Reset the graph so the next activation rebuilds it fresh.
        // AVAudioSession is deactivated here, which may change hardware format
        // (sample rate / channel count) — the existing node connections become
        // stale. We must rebuild to pick up the new format on re-activation.
        engine.reset()
        isGraphBuilt = false
        sessionManager.deactivate()
        state = .idle
    }

    func setNoiseCancellationEnabled(_ enabled: Bool) {
        configurationLock.lock()
        defer { configurationLock.unlock() }
        noiseCancellationEnabled = enabled
    }

    // MARK: - Volume Controls

    /// Sets mic volume. Slider range 0…1 maps to 0…+12 dB (0×…4× linear gain).
    func setMicrophoneVolume(_ value: Float) {
        // 0.0 → -96 dB (silence), 1.0 → +12.04 dB (4× boost)
        micGainNode.globalGain = value > 0 ? 20 * log10(value * 4) : -96
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
            state = .interrupted(reason: .unknown)
            removeMeteringTaps()
        case .ended:
            Task { try? await resume() }
        @unknown default:
            break
        }
    }

    func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
        if reason == .oldDeviceUnavailable, state == .active {
            // Headphones unplugged — pause music to avoid unexpected speaker output
            playerNode.pause()
        }
    }

    func handleMediaServicesReset() {
        // After a media services crash the entire audio graph is invalidated.
        // Reset isGraphBuilt so activate() rebuilds it from scratch.
        engine.stop()
        isGraphBuilt = false
        isMicTapInstalled = false
        isMusicTapInstalled = false
        state = .idle
        Task { try? await activate() }
    }

    // MARK: - Diagnostics

    var diagnostics: AudioSessionDiagnostics {
        sessionManager.diagnostics
    }

    /// AVAudioEngine does not expose a direct CPU load API in normal render mode.
    /// Returns 0; use Instruments on device for real measurements.
    var engineCPULoad: Float { 0 }

    // MARK: - Private — Graph

    private func buildGraph() throws {
        let inputNode = engine.inputNode
        let mainMixer = engine.mainMixerNode

        // Read input format AFTER AVAudioSession is active so sample rate is valid.
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(
                domain: "AudioEngineManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid input format — sample rate is 0. Is AVAudioSession active?"]
            )
        }

        // Standard stereo format at the hardware sample rate (used for music path).
        let stereoFormat = AVAudioFormat(
            standardFormatWithSampleRate: inputFormat.sampleRate,
            channels: 2
        )!

        // Configure micGainNode: 1 band bypassed, globalGain = +12 dB (4×).
        // The band must be configured even if bypassed; AVAudioUnitEQ requires
        // numberOfBands ≥ 1 and each band must have a valid frequency.
        let gainBand = micGainNode.bands[0]
        gainBand.filterType = .parametric
        gainBand.frequency  = 1000   // centre freq — irrelevant when bypass=true
        gainBand.bandwidth  = 1.0
        gainBand.gain       = 0
        gainBand.bypass     = true   // band is off; only globalGain applies
        micGainNode.globalGain = 12.04  // +12.04 dB ≈ 4× linear

        // Configure reverb (off by default)
        reverbNode.loadFactoryPreset(.smallRoom)
        reverbNode.wetDryMix = 0

        // Mic mixer at unity (gain is handled by micGainNode)
        micMixerNode.outputVolume = 1.0

        // Attach all custom nodes
        engine.attach(micGainNode)
        engine.attach(micMixerNode)
        engine.attach(musicMixerNode)
        engine.attach(playerNode)
        engine.attach(eqNode)
        engine.attach(reverbNode)

        // Microphone path:
        //   inputNode (mono hw format) → micGainNode → micMixerNode → reverbNode → eqNode → mainMixerNode
        engine.connect(inputNode,    to: micGainNode,  format: inputFormat)
        engine.connect(micGainNode,  to: micMixerNode, format: inputFormat)
        engine.connect(micMixerNode, to: reverbNode,   format: inputFormat)
        engine.connect(reverbNode,   to: eqNode,       format: inputFormat)
        engine.connect(eqNode,       to: mainMixer,    format: inputFormat)

        // Music path:
        //   playerNode → musicMixerNode → mainMixerNode
        //   Use explicit stereo format; nil format on playerNode output causes -10868.
        engine.connect(playerNode,     to: musicMixerNode, format: stereoFormat)
        engine.connect(musicMixerNode, to: mainMixer,      format: stereoFormat)

        // DO NOT manually connect mainMixerNode → outputNode.
        // AVAudioEngine owns that connection automatically.

        engine.prepare()
    }

    private func resume() async throws {
        guard case .interrupted = state else { return }
        try sessionManager.activate(noiseCancellationEnabled: currentNoiseCancellationEnabled())
        try engine.start()
        state = .active
        installMeteringTaps()
    }

    private func currentNoiseCancellationEnabled() -> Bool {
        configurationLock.lock()
        defer { configurationLock.unlock() }
        return noiseCancellationEnabled
    }

    // MARK: - Metering taps (~15 FPS, battery-friendly)
    //
    // Taps MUST be installed on intermediate mixer nodes, NOT on inputNode directly,
    // because inputNode is already connected in the graph. Installing a second tap on
    // inputNode after buildGraph() would detach it from the graph or cause an engine error.

    private func installMeteringTaps() {
        // Mic level: tap micMixerNode output (post-gain, pre-reverb)
        if !isMicTapInstalled {
            let micFormat = micMixerNode.outputFormat(forBus: 0)
            micMixerNode.installTap(onBus: 0, bufferSize: 1024, format: micFormat) { [weak self] buffer, _ in
                self?.updateMicLevel(buffer: buffer)
            }
            isMicTapInstalled = true
        }

        // Music level: tap musicMixerNode output
        if !isMusicTapInstalled {
            let musicFormat = musicMixerNode.outputFormat(forBus: 0)
            musicMixerNode.installTap(onBus: 0, bufferSize: 1024, format: musicFormat) { [weak self] buffer, _ in
                self?.updateMusicLevel(buffer: buffer)
            }
            isMusicTapInstalled = true
        }
    }

    private func removeMeteringTaps() {
        if isMicTapInstalled {
            micMixerNode.removeTap(onBus: 0)
            isMicTapInstalled = false
        }
        if isMusicTapInstalled {
            musicMixerNode.removeTap(onBus: 0)
            isMusicTapInstalled = false
        }
        DispatchQueue.main.async {
            self.micPeakLevel = 0
            self.musicPeakLevel = 0
        }
    }

    // MARK: - Level calculation (realtime-safe: no allocations, no locks)

    private func updateMicLevel(buffer: AVAudioPCMBuffer) {
        let peak = peakLevel(buffer: buffer)
        DispatchQueue.main.async { self.micPeakLevel = peak }
    }

    private func updateMusicLevel(buffer: AVAudioPCMBuffer) {
        let peak = peakLevel(buffer: buffer)
        DispatchQueue.main.async { self.musicPeakLevel = peak }
    }

    /// Returns the peak absolute sample value (0…1) from the first channel of a PCM buffer.
    private func peakLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        var peak: Float = 0
        for i in 0..<frameCount {
            let s = abs(data[i])
            if s > peak { peak = s }
        }
        return min(peak, 1.0)
    }
}
