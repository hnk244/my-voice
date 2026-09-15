import Foundation

/// Explicit state machine for the audio engine lifecycle.
enum AudioEngineState: Equatable {
    case idle
    case starting
    case active
    case stopping
    case interrupted(reason: InterruptionReason)
    case error(String)

    static func == (lhs: AudioEngineState, rhs: AudioEngineState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.starting, .starting), (.active, .active), (.stopping, .stopping):
            return true
        case (.interrupted(let a), .interrupted(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }

    var isActive: Bool { self == .active }
    var isIdle: Bool { self == .idle }
}

enum InterruptionReason: Equatable {
    case phoneCall
    case siri
    case alarm
    case otherApp
    case unknown
}
