import AVFoundation

/// Simple gain stage — adjusts output volume of a mixer node.
struct GainProcessor {
    weak var mixerNode: AVAudioMixerNode?

    init(mixerNode: AVAudioMixerNode) {
        self.mixerNode = mixerNode
    }

    /// 0.0 = silence, 1.0 = unity gain.
    func setGain(_ gain: Float) {
        mixerNode?.outputVolume = max(0, min(1, gain))
    }
}
