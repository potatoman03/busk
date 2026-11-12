import AVFoundation

/// Speaks short coaching cues with on-device speech synthesis.
@MainActor
final class CoachVoice: NSObject {
    private let synth = AVSpeechSynthesizer()
    var enabled = true
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate * 1.05
    private(set) var spoken: [String] = []

    func prepareAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true)
    }

    func say(_ text: String, interrupt: Bool = true) {
        spoken.append(text)
        guard enabled else { return }
        if interrupt && synth.isSpeaking { synth.stopSpeaking(at: .word) }
        let u = AVSpeechUtterance(string: text)
        u.rate = rate
        u.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier.hasPrefix("en") ? Locale.current.identifier : "en-US")
            ?? AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}
