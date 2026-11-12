import AVFoundation

/// Speaks short coaching cues with on-device speech synthesis.
@MainActor
final class CoachVoice: NSObject {
    private let synth = AVSpeechSynthesizer()
    var enabled = true
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate * 1.05
    private(set) var spoken: [String] = []

    /// Set while voice commands are listening, so speaking cues doesn't close the microphone.
    static var keepsMicrophoneOpen = false

    func prepareAudioSession() {
        Self.configureAudioSession()
    }

    static func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        if keepsMicrophoneOpen {
            try? session.setCategory(.playAndRecord, mode: .default,
                                     options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP, .duckOthers, .mixWithOthers])
        } else {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        }
        try? session.setActive(true)
    }

    /// `force` speaks even when the coach is muted, for answers the player asked for.
    func say(_ text: String, interrupt: Bool = true, force: Bool = false) {
        spoken.append(text)
        guard enabled || force else { return }
        if interrupt && synth.isSpeaking { synth.stopSpeaking(at: .word) }
        let u = AVSpeechUtterance(string: text)
        u.rate = rate
        u.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier.hasPrefix("en") ? Locale.current.identifier : "en-US")
            ?? AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}
