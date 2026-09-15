import SwiftUI

/// Main karaoke monitoring screen.
struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var showFilePicker = false
    @State private var showDiagnostics = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 28) {
                    // Header
                    headerSection

                    // Status indicator
                    statusIndicator

                    // Level meters
                    levelMetersSection

                    // Volume controls
                    volumeControlsSection

                    Spacer()

                    // Music picker
                    musicSection

                    // Active / Stop button
                    activeButton

                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle("MyVoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showDiagnostics = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundColor(Theme.accent)
                    }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                MusicPickerView { url in
                    appState.selectMusic(url: url)
                }
            }
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView()
            }
            .alert("Error", isPresented: Binding(
                get: { appState.errorMessage != nil },
                set: { if !$0 { appState.errorMessage = nil } }
            )) {
                Button("OK") { appState.errorMessage = nil }
            } message: {
                Text(appState.errorMessage ?? "")
            }
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 4) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundColor(appState.engineState.isActive ? Theme.accent : .secondary)
                .symbolEffect(.pulse, isActive: appState.engineState.isActive)

            if !appState.currentAudioRoute.isEmpty {
                Text(appState.currentAudioRoute)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 12)
    }

    private var statusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stateColor)
                .frame(width: 10, height: 10)
            Text(stateLabel)
                .font(.headline)
                .foregroundColor(stateColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(stateColor.opacity(0.12), in: Capsule())
    }

    private var levelMetersSection: some View {
        VStack(spacing: 12) {
            LevelMeterRow(label: "Mic", level: appState.micLevel, color: Theme.accent)
            LevelMeterRow(label: "Music", level: appState.musicLevel, color: .blue)
        }
        .opacity(appState.engineState.isActive ? 1 : 0.4)
        .animation(.easeInOut, value: appState.engineState.isActive)
    }

    private var volumeControlsSection: some View {
        VStack(spacing: 16) {
            LabeledSlider(label: "Mic Volume", value: $appState.micVolume)
            LabeledSlider(label: "Music Volume", value: $appState.musicVolume)
            LabeledSlider(label: "Master Volume", value: $appState.masterVolume)
        }
    }

    private var musicSection: some View {
        HStack {
            Image(systemName: "music.note")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                if let url = appState.selectedMusicURL {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.subheadline)
                        .lineLimit(1)
                    HStack(spacing: 12) {
                        Button(action: appState.togglePlayback) {
                            Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                        }
                        .disabled(!appState.engineState.isActive)
                    }
                    .font(.title3)
                    .foregroundColor(Theme.accent)
                } else {
                    Text("No song selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button("Select") { showFilePicker = true }
                .font(.subheadline)
                .tint(Theme.accent)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var activeButton: some View {
        Button(action: toggleEngine) {
            Text(appState.engineState.isActive ? "STOP" : "ACTIVE")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(appState.engineState.isActive ? Color.red : Theme.accent)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(appState.engineState == .starting || appState.engineState == .stopping)
    }

    // MARK: - Helpers

    private var stateLabel: String {
        switch appState.engineState {
        case .idle: return "INACTIVE"
        case .starting: return "STARTING…"
        case .active: return "● ACTIVE"
        case .stopping: return "STOPPING…"
        case .interrupted: return "INTERRUPTED"
        case .error(let msg): return "ERROR: \(msg)"
        }
    }

    private var stateColor: Color {
        switch appState.engineState {
        case .active: return .green
        case .interrupted: return .orange
        case .error: return .red
        default: return .secondary
        }
    }

    private func toggleEngine() {
        if appState.engineState.isActive {
            appState.deactivate()
        } else {
            appState.activate()
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
}
