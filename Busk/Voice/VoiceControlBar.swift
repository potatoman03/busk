import SwiftUI

/// Shows whether Busk is listening and what it last heard. Without a microphone (simulator, UI tests) it also shows
/// buttons that inject each command's phrase as if it had been spoken.
struct VoiceControlBar: View {
    @Environment(VoiceControl.self) private var voice: VoiceControl?
    /// The commands that do something on this screen, first one used as the hint.
    let commands: [VoiceCommand]
    /// Short landscape column: put the buttons beside the status when they fit.
    var compact = false

    var body: some View {
        if let voice, voice.state != .off {
            if compact {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { content(voice) }
                    VStack(spacing: 6) { content(voice) }
                }
            } else {
                VStack(spacing: 6) { content(voice) }
            }
        }
    }

    @ViewBuilder private func content(_ voice: VoiceControl) -> some View {
                Label(statusText(voice), systemImage: icon(voice))
                    .font(.caption.bold())
                    .lineLimit(1)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("voiceStatus")
                if voice.state == .simulated {
                    ViewThatFits {
                        HStack(spacing: 6) { buttons(commands, voice) }
                        VStack(spacing: 6) {
                            HStack(spacing: 6) { buttons(Array(commands.prefix(2)), voice) }
                            HStack(spacing: 6) { buttons(Array(commands.dropFirst(2)), voice) }
                        }
                    }
                }
    }

    private func buttons(_ commands: [VoiceCommand], _ voice: VoiceControl) -> some View {
        ForEach(commands, id: \.self) { command in
            Button("“\(command.example.capitalizedFirst)”") { voice.inject(command.example) }
                .font(.caption2.bold())
                .buttonStyle(.bordered)
                .accessibilityIdentifier("simulateVoice-\(command.rawValue)")
        }
    }

    private func statusText(_ voice: VoiceControl) -> String {
        let hint = "Say " + commands.prefix(2).map { "“\($0.example)”" }.joined(separator: " or ")
        switch voice.state {
        case .off: return ""
        case .listening: return voice.lastHeard.map { "Heard “\($0)”" } ?? hint
        case .simulated: return voice.lastHeard.map { "Heard “\($0)” (simulated mic)" } ?? "Simulated mic · " + hint
        case .needsPermission: return "Voice commands need microphone and speech access"
        case .unavailable(let reason): return reason
        }
    }

    private func icon(_ voice: VoiceControl) -> String {
        switch voice.state {
        case .listening, .simulated: return "mic.fill"
        default: return "mic.slash"
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
