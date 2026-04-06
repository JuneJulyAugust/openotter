import AVFoundation

protocol SpeechOutputting {
    func speak(_ text: String)
    var isEnabled: Bool { get set }
}

final class SpeechOutput: SpeechOutputting {

    var isEnabled: Bool = true

    /// Best English voice available on this device.
    /// Prefers premium (neural) > enhanced > default.
    private static let preferredVoice: AVSpeechSynthesisVoice? = {
        let english = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        return english.first { $0.quality == .premium }
            ?? english.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    /// Create a fresh synthesizer for each utterance.
    /// AVSpeechSynthesizer has a known bug where it enters a permanently
    /// silent state after stopSpeaking + speak cycles. Fresh instances avoid this.
    private var synthesizer: AVSpeechSynthesizer?

    func speak(_ text: String) {
        guard isEnabled else { return }

        // Configure audio session for speech output.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: .mixWithOthers)
        try? session.setActive(true)

        // Tear down old synthesizer and create fresh one.
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
        let synth = AVSpeechSynthesizer()
        synthesizer = synth

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.preferredVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.volume = 1.0
        synth.speak(utterance)
    }
}


/// Silent implementation for tests and debug.
final class MuteSpeechOutput: SpeechOutputting {
    var isEnabled: Bool = false
    var lastSpoken: String?

    func speak(_ text: String) {
        lastSpoken = text
    }
}
