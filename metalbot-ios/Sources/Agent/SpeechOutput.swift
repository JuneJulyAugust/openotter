import AVFoundation

protocol SpeechOutputting {
    func speak(_ text: String)
    var isEnabled: Bool { get set }
}

final class SpeechOutput: SpeechOutputting {

    var isEnabled: Bool = true

    private let synthesizer = AVSpeechSynthesizer()

    /// Best English voice available on this device.
    /// Prefers premium (neural) > enhanced > default.
    /// Premium voices must be downloaded in Settings > Accessibility > Spoken Content > Voices.
    private static let preferredVoice: AVSpeechSynthesisVoice? = {
        let english = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        return english.first { $0.quality == .premium }
            ?? english.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    func speak(_ text: String) {
        guard isEnabled else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = SpeechOutput.preferredVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
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
