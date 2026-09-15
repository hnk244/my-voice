import AVFoundation

/// Wraps AVAudioUnitEQ with convenient 3-band control.
final class EQProcessor {
    let node: AVAudioUnitEQ

    enum Band: Int {
        case low = 0, mid = 1, high = 2
    }

    init() {
        node = AVAudioUnitEQ(numberOfBands: 3)
        configureBands()
    }

    private func configureBands() {
        let params = node.bands

        // Low shelf ~200 Hz
        params[Band.low.rawValue].filterType = .lowShelf
        params[Band.low.rawValue].frequency = 200
        params[Band.low.rawValue].gain = 0
        params[Band.low.rawValue].bypass = false

        // Parametric ~1 kHz
        params[Band.mid.rawValue].filterType = .parametric
        params[Band.mid.rawValue].frequency = 1000
        params[Band.mid.rawValue].bandwidth = 1
        params[Band.mid.rawValue].gain = 0
        params[Band.mid.rawValue].bypass = false

        // High shelf ~8 kHz
        params[Band.high.rawValue].filterType = .highShelf
        params[Band.high.rawValue].frequency = 8000
        params[Band.high.rawValue].gain = 0
        params[Band.high.rawValue].bypass = false
    }

    func setGain(_ gain: Float, band: Band) {
        node.bands[band.rawValue].gain = gain
    }

    func reset() {
        node.bands.forEach { $0.gain = 0 }
    }
}
