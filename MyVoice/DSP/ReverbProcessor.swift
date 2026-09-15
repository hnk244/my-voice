import AVFoundation

/// Wraps AVAudioUnitReverb for easy wet/dry control.
final class ReverbProcessor {
    let node: AVAudioUnitReverb

    init() {
        node = AVAudioUnitReverb()
        node.loadFactoryPreset(.mediumHall)
        node.wetDryMix = 0 // dry by default
    }

    /// 0 = fully dry, 100 = fully wet.
    func setWetDryMix(_ value: Float) {
        node.wetDryMix = max(0, min(100, value))
    }
}
