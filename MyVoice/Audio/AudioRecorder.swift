import AVFoundation

/// Records the mixed audio output from the main mixer node to a file.
final class AudioRecorder {

    private var audioFile: AVAudioFile?
    private(set) var isRecording = false

    func start(url: URL, format: AVAudioFormat) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        audioFile = try AVAudioFile(forWriting: url, settings: settings)
        isRecording = true
    }

    /// Called from the audio tap — must be realtime-safe (no blocking).
    func write(buffer: AVAudioPCMBuffer) {
        guard isRecording, let file = audioFile else { return }
        try? file.write(from: buffer)
    }

    func stop() {
        isRecording = false
        audioFile = nil
    }

    /// Convenience URL in the app's Documents folder.
    static func newRecordingURL(ext: String = "m4a") -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let name = "recording-\(formatter.string(from: Date())).\(ext)"
        return docs.appendingPathComponent(name)
    }
}
