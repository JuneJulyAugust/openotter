import AVFoundation

protocol SpeechOutputting {
    func speak(_ text: String)
    var isEnabled: Bool { get set }
}

final class SpeechOutput: SpeechOutputting {

    var isEnabled: Bool = true

    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        guard isEnabled else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
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
