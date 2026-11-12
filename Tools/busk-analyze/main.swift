import CoreGraphics
import Foundation

// busk-analyze --video CLIP.mp4 --handedness right|left --output OUT.json [--keypoints CLIP.keypoints.json] [--view side|front]
// Contract: benchmark/README.md. Poses come from Apple Vision on the video unless keypoints are given.

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(2)
}

var opts: [String: String] = [:]
var args = CommandLine.arguments.dropFirst().makeIterator()
while let a = args.next() {
    guard a.hasPrefix("--"), let v = args.next() else { fail("bad argument \(a)") }
    opts[String(a.dropFirst(2))] = v
}
guard let output = opts["output"] else { fail("--output is required") }
let handedness = Handedness(rawValue: opts["handedness"] ?? "right") ?? .right

var frames: [PoseFrame]
var view = opts["view"].flatMap(CameraView.init(rawValue:))
let poseSource: String
if let kpPath = opts["keypoints"] {
    guard let data = FileManager.default.contents(atPath: kpPath),
          let kp = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let raw = kp["frames"] as? [[String: Any]] else { fail("cannot read keypoints \(kpPath)") }
    let fps = (kp["fps"] as? Double) ?? 30
    let aspect = CGFloat((kp["width"] as? Double ?? 1) / (kp["height"] as? Double ?? 1))
    view = view ?? (kp["view"] as? String).flatMap(CameraView.init(rawValue:))
    frames = raw.enumerated().map { i, f in
        var joints: [Joint: CGPoint] = [:]
        for (name, v) in (f["joints"] as? [String: Any]) ?? [:] {
            let parts = name.split(separator: "_")
            let camel = parts.prefix(1).joined() + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
            guard let j = Joint(rawValue: camel), let xy = v as? [Double], xy.count >= 2 else { continue }
            joints[j] = CGPoint(x: xy[0], y: xy[1])
        }
        return PoseFrame(timestamp: (f["t"] as? Double) ?? Double(i) / fps, joints: joints, aspect: aspect)
    }
    poseSource = "benchmark-keypoints"
} else {
    guard let video = opts["video"] else { fail("--video is required") }
    do { frames = try VideoPoses.read(URL(fileURLWithPath: video), handedness: handedness,live: opts["live-tracking"] == "1") } catch { fail("\(error)") }
    poseSource = "vision"
}

/// Front-on, both shoulders are spread apart; side-on, they overlap. In between (a three-quarter angle, or noisy
/// pose) the view stays unknown and only checks that work from any angle are run.
func inferView(_ frames: [PoseFrame]) -> CameraView? {
    let ratios = frames.compactMap { f -> Double? in
        guard let l = f.point(.leftShoulder), let r = f.point(.rightShoulder), let n = f.point(.neck), let root = f.point(.root) else { return nil }
        let torso = Geometry.distance(n, root)
        return torso > 0 ? Double(abs(l.x - r.x)) / torso : nil
    }.sorted()
    guard !ratios.isEmpty else { return nil }
    let median = ratios[ratios.count / 2]
    // Only clear-cut clips: a three-quarter angle reads anywhere from 0.25 to 0.65, so those stay unknown (pass --view).
    return median > 0.75 ? .front : median < 0.2 ? .side : nil
}
let cameraView = view ?? inferView(frames)

// `--save-keypoints OUT.json` writes the tracked shooter's pose as a `busk-bench-keypoints/1` sidecar, which the app's
// `-videoPath` replays where Vision can't run (the simulator).
if let dump = opts["save-keypoints"] ?? opts["dump-poses"] {
    let names: [Joint: String] = Dictionary(uniqueKeysWithValues: Joint.allCases.map { j in
        (j, j.rawValue.replacingOccurrences(of: "([A-Z])", with: "_$1", options: .regularExpression).lowercased())
    })
    let duration = (frames.last?.timestamp ?? 0) - (frames.first?.timestamp ?? 0)
    let doc: [String: Any] = [
        "format": "busk-bench-keypoints/1", "source": "busk-analyze",
        "fps": frames.count > 1 && duration > 0 ? Double(frames.count - 1) / duration : 30,
        "width": Double(frames.first?.aspect ?? 1), "height": 1.0,
        "view": cameraView?.rawValue ?? "unknown", "handedness": handedness.rawValue,
        "frames": frames.map { f in
            ["t": f.timestamp, "joints": Dictionary(uniqueKeysWithValues: f.joints.map { (names[$0.key]!, [Double($0.value.x), Double($0.value.y)]) })] as [String: Any]
        },
    ]
    try? JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys]).write(to: URL(fileURLWithPath: dump))
}

let analyzer = ShotAnalyzer(handedness: handedness, view: cameraView)
let evaluator = FormEvaluator()
var shots: [[String: Any]] = []
// Hold the last pose so a follow-through still in progress when the clip ends can finish.
if let last = frames.last {
    let dt = frames.count > 1 ? (last.timestamp - frames[0].timestamp) / Double(frames.count - 1) : 1.0 / 30
    for k in 1...Int(1.6 / max(dt, 1.0 / 240)) {
        var f = last
        f.timestamp += Double(k) * dt
        frames.append(f)
    }
}
for frame in frames {
    guard let m = analyzer.process(frame) else { continue }
    let r = evaluator.evaluate(m)
    shots.append([
        "feedback": r.fixes.isEmpty ? [r.cue] : r.fixes.map(\.cue),
        "flaws": r.fixes.map(\.flawID),
        "busk": [
            "score": r.score,
            "areas": Dictionary(uniqueKeysWithValues: r.areas.map { ($0.area.rawValue, ["grade": $0.grade.label, "value": $0.value]) }),
        ] as [String: Any],
    ])
}
let doc: [String: Any] = ["shots": shots, "pose_source": poseSource, "view": cameraView?.rawValue ?? "unknown"]
do {
    let out = try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
    try out.write(to: URL(fileURLWithPath: output))
} catch { fail("cannot write \(output): \(error)") }
