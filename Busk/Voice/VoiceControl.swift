import AVFoundation
import Foundation
import Observation
import OSLog
import Speech

/// One recognized command, delivered to whichever screen is showing.
struct VoiceEvent: Equatable {
    let id: Int
    let command: VoiceCommand
    let transcript: String
}

/// Listens for hands-free commands ("start session", "how am I doing", "end session") with on-device speech
/// recognition. In the simulator and UI tests there is no microphone, so transcripts are injected instead and go
/// through the same parsing path.
@MainActor
@Observable
final class VoiceControl {
    enum State: Equatable {
        case off
        /// No microphone here: transcripts come from `inject(_:)`.
        case simulated
        case listening
        case needsPermission
        case unavailable(String)
    }

    private(set) var state: State = .off
    /// The last transcript that triggered a command.
    private(set) var lastHeard: String?
    /// The latest command. Screens react with `onChange(of:)`.
    private(set) var event: VoiceEvent?

    @ObservationIgnored private let simulateInput: Bool
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let tapTarget = RecognitionRequestBox()
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var restartTimer: Timer?
    @ObservationIgnored private var configObserver: NSObjectProtocol?
    @ObservationIgnored private var lastCommandAt = Date.distantPast
    @ObservationIgnored private let clock: () -> Date

    init(simulateInput: Bool = AppEnvironment.simulateVoiceInput, clock: @escaping () -> Date = Date.init) {
        self.simulateInput = simulateInput
        self.clock = clock
    }

    var isActive: Bool { state == .simulated || state == .listening }

    func start() async {
        guard state == .off || state == .needsPermission else { return }
        if simulateInput {
            state = .simulated
            return
        }
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            state = .unavailable("Voice commands need on-device speech recognition")
            return
        }
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        let mic = await AVAudioApplication.requestRecordPermission()
        guard speech == .authorized, mic else {
            state = .needsPermission
            return
        }
        CoachVoice.keepsMicrophoneOpen = true
        CoachVoice.configureAudioSession()
        do {
            try startEngine()
        } catch {
            Self.log.error("voice commands: audio engine failed: \(error.localizedDescription, privacy: .public)")
            state = .unavailable("Microphone unavailable")
            return
        }
        state = .listening
        beginRecognition()
        // Apple caps one recognition request at about a minute, so start a fresh one well before that.
        restartTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.beginRecognition() }
        }
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartEngine() }
        }
    }

    func stop() {
        restartTimer?.invalidate()
        restartTimer = nil
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        task?.cancel()
        task = nil
        tapTarget.request?.endAudio()
        tapTarget.request = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        CoachVoice.keepsMicrophoneOpen = false
        state = .off
    }

    /// Feeds a transcript through the same path as the microphone. Used by the simulator buttons and tests.
    func inject(_ transcript: String) {
        heard(transcript)
    }

    /// Returns the command it fired, if any.
    @discardableResult
    func heard(_ transcript: String) -> VoiceCommand? {
        guard isActive, let command = VoiceCommandParser.command(in: transcript) else { return nil }
        let now = clock()
        // One utterance shows up in several partial results; fire once.
        guard now.timeIntervalSince(lastCommandAt) > 1.5 else { return nil }
        lastCommandAt = now
        lastHeard = transcript
        event = VoiceEvent(id: (event?.id ?? 0) + 1, command: command, transcript: transcript)
        Self.log.notice("voice command \(command.rawValue, privacy: .public): \(transcript, privacy: .public)")
        // Start a fresh transcript so the same words are not matched again.
        if state == .listening { beginRecognition() }
        return command
    }

    private func startEngine() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw VoiceControlError.noMicrophone }
        let target = tapTarget
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            target.request?.append(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private func restartEngine() {
        guard state == .listening else { return }
        engine.stop()
        do {
            try startEngine()
            beginRecognition()
        } catch {
            state = .unavailable("Microphone unavailable")
        }
    }

    private func beginRecognition() {
        guard state == .listening, let recognizer else { return }
        task?.cancel()
        tapTarget.request?.endAudio()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = VoiceCommandParser.contextualStrings
        tapTarget.request = request
        generation += 1
        let gen = generation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in self?.recognized(text, done: done, generation: gen) }
        }
    }

    private func recognized(_ text: String?, done: Bool, generation gen: Int) {
        guard gen == generation else { return }
        if let text, heard(text) != nil { return }
        if done {
            // Silence or an error ends a request; keep listening with a new one.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, gen == self.generation else { return }
                self.beginRecognition()
            }
        }
    }

    private static let log = Logger(subsystem: "com.potatoman03.busk", category: "voice-commands")
}

enum VoiceControlError: Error {
    case noMicrophone
}

/// Holds the live request so the audio tap (on the audio thread) can append buffers to it.
private final class RecognitionRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _request: SFSpeechAudioBufferRecognitionRequest?
    var request: SFSpeechAudioBufferRecognitionRequest? {
        get { lock.withLock { _request } }
        set { lock.withLock { _request = newValue } }
    }
}
