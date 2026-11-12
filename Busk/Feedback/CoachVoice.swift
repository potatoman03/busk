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
    /// Music is turned down under the cues only while a session is live.
    private(set) static var ducksMusic = false
    /// Posted when a session ends while voice commands hold the microphone: the listener has to restart its engine.
    static let audioSessionReset = Notification.Name("CoachVoice.audioSessionReset")

    func prepareAudioSession() {
        Self.ducksMusic = true
        Self.configureAudioSession()
    }

    static func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.mixWithOthers]
        if ducksMusic { options.insert(.duckOthers) }
        if keepsMicrophoneOpen {
            try? session.setCategory(.playAndRecord, mode: .default,
                                     options: options.union([.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]))
        } else {
            try? session.setCategory(.playback, mode: .spokenAudio, options: options)
        }
        try? session.setActive(true)
    }

    /// Lets music the cues ducked come back up once a session is over.
    static func deactivateAudioSession() {
        ducksMusic = false
        // Ducking only lifts when the session deactivates, even if voice commands still need the microphone.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard keepsMicrophoneOpen else { return }
        configureAudioSession()
        NotificationCenter.default.post(name: audioSessionReset, object: nil)
    }

    /// `force` speaks even when the coach is muted, for answers the player asked for.
    func say(_ text: String, interrupt: Bool = true, force: Bool = false) {
        spoken.append(text)
        guard enabled || force else { return }
        if interrupt && synth.isSpeaking { synth.stopSpeaking(at: .word) }
        let u = AVSpeechUtterance(string: text)
        u.rate = rate
        // The user's own English accent (en-GB, en-AU...) when they have one; cues are written in English.
        let code = AVSpeechSynthesisVoice.currentLanguageCode()
        u.voice = AVSpeechSynthesisVoice(language: code.hasPrefix("en") ? code : "en-US") ?? AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}
