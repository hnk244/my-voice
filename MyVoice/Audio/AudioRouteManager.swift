import AVFoundation
import Combine

/// Observes AVAudioSession route changes and interruptions,
/// forwarding events to the AudioEngineManager.
final class AudioRouteManager: ObservableObject {

    @Published var currentRoute: String = ""
    @Published var currentOutputPortType: String = ""

    private weak var engine: AudioEngineManager?
    private var observers: [NSObjectProtocol] = []

    init(engine: AudioEngineManager) {
        self.engine = engine
        updateRoute()
        registerObservers()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Private

    private func updateRoute() {
        let session = AVAudioSession.sharedInstance()
        let output = session.currentRoute.outputs.first?.portName ?? "Unknown"
        let input = session.currentRoute.inputs.first?.portName ?? "None"
        currentOutputPortType = session.currentRoute.outputs.first?.portType.rawValue ?? ""
        currentRoute = "\(input) → \(output)"
    }

    private func registerObservers() {
        let center = NotificationCenter.default

        let routeObs = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }

        let interruptionObs = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        let lostObs = center.addObserver(
            forName: AVAudioSession.mediaServicesWereLostNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.engine?.handleMediaServicesReset()
        }

        let resetObs = center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.engine?.handleMediaServicesReset()
        }

        observers = [routeObs, interruptionObs, lostObs, resetObs]
    }

    private func handleRouteChange(_ notification: Notification) {
        updateRoute()

        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        engine?.handleRouteChange(reason: reason)
    }

    private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        engine?.handleInterruption(type: type)
    }
}
