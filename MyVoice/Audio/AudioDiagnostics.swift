import AVFoundation

/// Collects and exposes real-time audio diagnostics for the debug panel.
struct AudioDiagnostics {
    let sessionDiagnostics: AudioSessionDiagnostics
    let engineRunning: Bool
    let cpuLoad: Float

    var session: AudioSessionDiagnostics { sessionDiagnostics }

    init(sessionManager: AudioSessionManager, engineManager: AudioEngineManager) {
        self.sessionDiagnostics = sessionManager.diagnostics
        self.engineRunning = engineManager.state == .active
        self.cpuLoad = engineManager.engineCPULoad
    }

    var description: String {
        """
        === Audio Diagnostics ===
        Category:      \(sessionDiagnostics.category)
        Mode:          \(sessionDiagnostics.mode)
        Noise Cancel:  \(sessionDiagnostics.noiseCancellationEnabled ? "On" : "Off")
        Sample Rate:   \(Int(sessionDiagnostics.sampleRate)) Hz
        Buffer:        \(String(format: "%.2f", sessionDiagnostics.ioBufferDuration * 1000)) ms
        Est. Latency:  \(String(format: "%.1f", sessionDiagnostics.estimatedLatencyMs)) ms
        Input:         \(sessionDiagnostics.inputRoute)
        Output:        \(sessionDiagnostics.outputRoute)
        In Channels:   \(sessionDiagnostics.inputChannels)
        Out Channels:  \(sessionDiagnostics.outputChannels)
        Engine:        \(engineRunning ? "Running" : "Stopped")
        CPU Load:      \(String(format: "%.1f", cpuLoad * 100))%
        """
    }
}
