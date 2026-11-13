import AVFoundation

/// Speaks short coaching cues with on-device speech synthesis.
@MainActor
@Observable
final class CoachVoice: NSObject, AVSpeechSynthesizerDelegate {
    @ObservationIgnored private let synth = AVSpeechSynthesizer()
    @ObservationIgnored var enabled = true
    @ObservationIgnored var rate: Float = AVSpeechUtteranceDefaultSpeechRate * 1.05
    @ObservationIgnored private(set) var spoken: [String] = []
    /// Keeps each cue in progress instead of playing it, until `stop()`, so UI tests can see the speaking state on
    /// a slow simulator.
    @ObservationIgnored var holdsSpeech = false
    /// Cues said but not yet finished, including ones still waiting for the voice lookup.
    private var inFlight: Set<ObjectIdentifier> = []
    var isSpeaking: Bool { !inFlight.isEmpty }

    /// Set while voice commands are listening, so speaking cues doesn't close the microphone.
    static var keepsMicrophoneOpen = false
    /// Music is turned down under the cues only while a session is live.
    private(set) static var ducksMusic = false
    /// Posted when a session ends while voice commands hold the microphone: the listener has to restart its engine.
    static let audioSessionReset = Notification.Name("CoachVoice.audioSessionReset")

    override init() {
        super.init()
        synth.delegate = self
        _ = Self.voiceLookup
    }

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

    /// Looking up the speech language is a synchronous call into a system service. On the main thread it froze the
    /// app for over a minute on a busy phone or CI simulator, so the voice is looked up once, off the main thread.
    private static let voiceLookup = Task.detached(priority: .userInitiated) { () -> VoiceBox in
        // The user's own English accent (en-GB, en-AU...) when they have one; cues are written in English.
        let code = AVSpeechSynthesisVoice.currentLanguageCode()
        return VoiceBox(voice: AVSpeechSynthesisVoice(language: code.hasPrefix("en") ? code : "en-US")
                        ?? AVSpeechSynthesisVoice(language: "en-US"))
    }
    private struct VoiceBox: @unchecked Sendable { let voice: AVSpeechSynthesisVoice? }
    /// Cues wait their turn behind the voice lookup, so they still play in the order they were said.
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    /// `force` speaks even when the coach is muted, for answers the player asked for.
    func say(_ text: String, interrupt: Bool = true, force: Bool = false) {
        spoken.append(text)
        guard enabled || force else { return }
        let u = AVSpeechUtterance(string: text)
        u.rate = rate
        let id = ObjectIdentifier(u)
        inFlight.insert(id)
        let previous = queue
        let run = generation
        queue = Task {
            await previous?.value
            u.voice = await Self.voiceLookup.value.voice
            guard run == generation else { return }
            guard !holdsSpeech else { return }
            if interrupt && synth.isSpeaking { synth.stopSpeaking(at: .word) }
            synth.speak(u)
        }
    }

    func stop() {
        generation += 1
        if !inFlight.isEmpty { inFlight.removeAll() }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    private nonisolated func finished(_ id: ObjectIdentifier) {
        Task { @MainActor in inFlight.remove(id) }
    }
}
