import AVFoundation

/// Manages the AVAudioSession lifecycle:
/// - category configuration
/// - activation / deactivation
/// - microphone permission
final class AudioSessionManager {
    private var currentMonitoringMode: MonitoringMode = .standard

    enum MonitoringMode {
        case standard
        case noiseCancellation

        var sessionMode: AVAudioSession.Mode {
            switch self {
            case .standard:
                return .default
            case .noiseCancellation:
                return .voiceChat
            }
        }
    }

    // MARK: - Errors

    enum SessionError: LocalizedError {
        case microphonePermissionDenied
        case sessionConfigurationFailed(Error)
        case sessionActivationFailed(Error)

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone permission is required. Please enable it in Settings."
            case .sessionConfigurationFailed(let e):
                return "Audio session configuration failed: \(e.localizedDescription)"
            case .sessionActivationFailed(let e):
                return "Audio session activation failed: \(e.localizedDescription)"
            }
        }
    }

    // MARK: - Public Interface

    /// Configure and activate the audio session for simultaneous recording + playback.
    func activate(noiseCancellationEnabled: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        let monitoringMode: MonitoringMode = noiseCancellationEnabled ? .noiseCancellation : .standard
        let options: AVAudioSession.CategoryOptions = noiseCancellationEnabled
        ? [.mixWithOthers, .allowBluetoothHFP]
        : [.mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP]
        do {
            try session.setCategory(
                .playAndRecord,
                mode: monitoringMode.sessionMode,
                options: options
            )
            try session.setPreferredIOBufferDuration(0.0029) // ~128 samples @ 44.1 kHz
            try session.setActive(true)
            currentMonitoringMode = monitoringMode
        } catch {
            throw SessionError.sessionActivationFailed(error)
        }
    }

    /// Deactivate the session, releasing microphone and stopping background audio.
    func deactivate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Diagnostics

    var diagnostics: AudioSessionDiagnostics {
        let session = AVAudioSession.sharedInstance()
        return AudioSessionDiagnostics(
            category: session.category.rawValue,
            mode: session.mode.rawValue,
            noiseCancellationEnabled: currentMonitoringMode == .noiseCancellation,
            sampleRate: session.sampleRate,
            ioBufferDuration: session.ioBufferDuration,
            inputRoute: session.currentRoute.inputs.first?.portName ?? "None",
            outputRoute: session.currentRoute.outputs.first?.portName ?? "None",
            inputChannels: session.inputNumberOfChannels,
            outputChannels: session.outputNumberOfChannels
        )
    }
}

struct AudioSessionDiagnostics {
    let category: String
    let mode: String
    let noiseCancellationEnabled: Bool
    let sampleRate: Double
    let ioBufferDuration: TimeInterval
    let inputRoute: String
    let outputRoute: String
    let inputChannels: Int
    let outputChannels: Int

    var estimatedLatencyMs: Double {
        ioBufferDuration * 1000 * 2 // input + output
    }
}
