import Foundation

/// What a player can say from the shooting spot.
enum VoiceCommand: String, CaseIterable, Sendable {
    case start, end, status, make, miss

    /// Phrases that trigger each command, lowercased without punctuation.
    var phrases: [String] {
        switch self {
        case .start: return ["start session", "start a session", "start the session", "start shooting", "start a new session",
                             "begin session", "go live", "lets go"]
        case .end: return ["end session", "end the session", "stop session", "stop the session", "finish session",
                           "end shooting", "stop shooting", "im done", "we are done", "were done"]
        case .status: return ["how am i doing", "how am i shooting", "hows my form", "how is my form", "how did i do",
                              "how m i doing", "give me a summary"]
        case .make: return ["made it", "make", "swish", "bucket", "count it", "that went in"]
        case .miss: return ["missed it", "miss", "missed", "brick", "no good"]
        }
    }

    /// The phrase shown as a hint and used by the simulator's voice buttons.
    var example: String { phrases[0] }
}

enum VoiceCommandParser {
    /// The command in a transcript. When several are said, the one said last wins.
    static func command(in transcript: String) -> VoiceCommand? {
        let text = " " + normalize(transcript) + " "
        var best: (command: VoiceCommand, position: String.Index)?
        for command in VoiceCommand.allCases {
            for phrase in command.phrases {
                guard let range = text.range(of: " \(phrase) ", options: .backwards) else { continue }
                if best == nil || range.upperBound > best!.position {
                    best = (command, range.upperBound)
                }
            }
        }
        return best?.command
    }

    /// Lowercases, drops apostrophes and turns other punctuation into spaces.
    static func normalize(_ transcript: String) -> String {
        let lowered = transcript.lowercased().replacingOccurrences(of: "\u{2019}", with: "").replacingOccurrences(of: "'", with: "")
        let mapped = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// Hints for the speech recognizer, so it favours command words.
    static var contextualStrings: [String] {
        ["start session", "end session", "how am I doing", "stop session", "I'm done", "made it", "missed it", "swish"]
    }
}
