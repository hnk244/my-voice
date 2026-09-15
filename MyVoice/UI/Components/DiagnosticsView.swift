import SwiftUI
import AVFoundation

/// Internal debug / diagnostics panel.
struct DiagnosticsView: View {
    @EnvironmentObject var appState: AppState
    @State private var diagnostics: AudioSessionDiagnostics?
    @State private var timer: Timer?

    var body: some View {
        NavigationStack {
            List {
                if let d = diagnostics {
                    Section("AVAudioSession") {
                        DiagRow(label: "Category", value: d.category)
                        DiagRow(label: "Mode", value: d.mode)
                        DiagRow(label: "Sample Rate", value: "\(Int(d.sampleRate)) Hz")
                        DiagRow(label: "IO Buffer", value: String(format: "%.2f ms", d.ioBufferDuration * 1000))
                        DiagRow(label: "Est. Latency", value: String(format: "%.1f ms", d.estimatedLatencyMs))
                        DiagRow(label: "Input", value: d.inputRoute)
                        DiagRow(label: "Output", value: d.outputRoute)
                        DiagRow(label: "In Channels", value: "\(d.inputChannels)")
                        DiagRow(label: "Out Channels", value: "\(d.outputChannels)")
                    }

                    Section("Engine") {
                        DiagRow(label: "State", value: "\(appState.engineState)")
                        DiagRow(label: "CPU Load", value: String(format: "%.1f%%", appState.audioEngine.engineCPULoad * 100))
                    }
                } else {
                    Text("Engine not active")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in refresh() }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func refresh() {
        diagnostics = appState.audioEngine.diagnostics
    }
}

private struct DiagRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label, value: value)
            .font(.system(.footnote, design: .monospaced))
    }
}
