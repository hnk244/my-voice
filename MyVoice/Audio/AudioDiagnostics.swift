import AVFoundation

/// Collects and exposes real-time audio diagnostics for the debug panel.
struct AudioDiagnostics {
    let session: AudioSessionDiagnostics
    let engineRunning: Bool
    let cpuLoad: Float

    init(sessionManager: AudioSessionManager, engineManager: AudioEngineManager) {
        self.session = sessionManager.diagnostics
        self.engineRunning = engineManager.state == .active
        self.cpuLoad = engineManager.engineCPULoad
    }

    var description: String {
        """
        === Audio Diagnostics ===
        Category:      \(session.category)
        Mode:          \(session.mode)
        Sample Rate:   \(Int(session.sampleRate)) Hz
        Buffer:        \(String(format: "%.2f", session.ioBufferDuration * 1000)) ms
        Est. Latency:  \(String(format: "%.1f", session.estimatedLatencyMs)) ms
        Input:         \(session.inputRoute)
        Output:        \(session.outputRoute)
        In Channels:   \(session.inputChannels)
        Out Channels:  \(session.outputChannels)
        Engine:        \(engineRunning ? "Running" : "Stopped")
        CPU Load:      \(String(format: "%.1f", cpuLoad * 100))%
        """
    }
}
