import Foundation

/// Proof that a `-replay-keypoints` run really played its clip, so a benchmark run can't pass on a stale screen.
/// Written to `Documents/replay-status.json` (or `-replay-status PATH`) when the clip loads (`finished: false`)
/// and again once every frame has gone through the live session.
struct ReplayStatus: Codable, Equatable {
    var label: String?
    var path: String
    var frames: Int
    var framesPlayed = 0
    var shots = 0
    var cues: [String] = []
    var finished = false

    static var url: URL {
        if let path = AppEnvironment.replayStatusPath { return URL(fileURLWithPath: path) }
        return URL.documentsDirectory.appending(path: "replay-status.json")
    }

    func write(to url: URL = ReplayStatus.url) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(self).write(to: url, options: .atomic)
    }
}
