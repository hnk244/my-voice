import Foundation
import Combine
import AVFoundation

/// Top-level application state shared across views.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Published State

    @Published var engineState: AudioEngineState = .idle
    @Published var micLevel: Float = 0
    @Published var musicLevel: Float = 0
    @Published var micVolume: Float = 1.0 {
        didSet { audioEngine.setMicrophoneVolume(micVolume) }
    }
    @Published var musicVolume: Float = 0.7 {
        didSet { audioEngine.setMusicVolume(musicVolume) }
    }
    @Published var masterVolume: Float = 1.0 {
        didSet { audioEngine.setMasterVolume(masterVolume) }
    }
    @Published var noiseCancellationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(noiseCancellationEnabled, forKey: Self.noiseCancellationKey)
            audioEngine.setNoiseCancellationEnabled(noiseCancellationEnabled)
        }
    }
    @Published var selectedMusicURL: URL?
    @Published var isPlaying: Bool = false
    @Published var errorMessage: String?
    @Published var currentAudioRoute: String = ""

    // MARK: - Services

    let audioEngine: AudioEngineManager
    let routeManager: AudioRouteManager

    private var cancellables = Set<AnyCancellable>()
    private static let noiseCancellationKey = "noiseCancellationEnabled"

    init() {
        let noiseCancellationEnabled = UserDefaults.standard.object(forKey: Self.noiseCancellationKey) as? Bool ?? false
        let engine = AudioEngineManager()
        self.noiseCancellationEnabled = noiseCancellationEnabled
        self.audioEngine = engine
        self.routeManager = AudioRouteManager(engine: engine)

        bindAudioEngine()
        audioEngine.setNoiseCancellationEnabled(noiseCancellationEnabled)
    }

    // MARK: - Actions

    func activate() {
        Task {
            do {
                try await audioEngine.activate()
                // engineState is driven by the Combine binding from audioEngine.$state
            } catch {
                errorMessage = error.localizedDescription
                // engine already reset its state to .idle; binding will sync it
            }
        }
    }

    func deactivate() {
        audioEngine.deactivate()
        // engineState synced via binding; just clear playback flag
        isPlaying = false
    }

    func selectMusic(url: URL) {
        selectedMusicURL = url
        do {
            try audioEngine.loadMusic(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePlayback() {
        if isPlaying {
            audioEngine.pauseMusic()
            isPlaying = false
        } else {
            audioEngine.playMusic()
            isPlaying = true
        }
    }

    // MARK: - Private

    private func bindAudioEngine() {
        audioEngine.$micPeakLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$micLevel)

        audioEngine.$musicPeakLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$musicLevel)

        audioEngine.$state
            .receive(on: DispatchQueue.main)
            .assign(to: &$engineState)

        routeManager.$currentRoute
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentAudioRoute)
    }
}
