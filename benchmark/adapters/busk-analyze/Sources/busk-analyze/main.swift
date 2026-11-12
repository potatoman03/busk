import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// Contract: busk-analyze --video V --handedness right|left --output OUT.json [--keypoints K.json]
// Feeds the benchmark's keypoints through busk's ShotAnalyzer -> FormEvaluator and writes what busk would say.

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(2)
}

var opts: [String: String] = [:]
var it = CommandLine.arguments.dropFirst().makeIterator()
while let a = it.next() {
    guard a.hasPrefix("--"), let v = it.next() else { fail("bad argument \(a)") }
    opts[String(a.dropFirst(2))] = v
}
guard let output = opts["output"] else { fail("--output is required") }
guard let kpPath = opts["keypoints"] else {
    fail("this adapter needs --keypoints: Vision pose detection only runs inside the iOS app")
}
let handedness = Handedness(rawValue: opts["handedness"] ?? "right") ?? .right

guard let data = FileManager.default.contents(atPath: kpPath),
      let kp = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let frames = kp["frames"] as? [[String: Any]] else { fail("cannot read keypoints \(kpPath)") }
let fps = (kp["fps"] as? Double) ?? 30
let view = CameraView(rawValue: kp["view"] as? String ?? "side") ?? .side

func joint(_ name: String) -> Joint? {
    let parts = name.split(separator: "_")
    guard let first = parts.first else { return nil }
    let camel = String(first) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    return Joint(rawValue: camel)
}

func poseFrame(_ f: [String: Any], _ t: Double) -> PoseFrame {
    var joints: [Joint: CGPoint] = [:]
    for (name, v) in (f["joints"] as? [String: Any]) ?? [:] {
        guard let j = joint(name), let xy = v as? [Double], xy.count >= 2 else { continue }
        joints[j] = CGPoint(x: xy[0], y: xy[1])
    }
    return PoseFrame(timestamp: t, joints: joints)
}

let flawFor: [FormArea: String] = [
    .elbow: "elbow_flare", .arc: "flat_arc", .releaseHeight: "low_set_point",
    .followThrough: "no_follow_through", .legs: "no_leg_drive",
]

let analyzer = ShotAnalyzer(handedness: handedness, view: view)
let evaluator = FormEvaluator()
var shots: [[String: Any]] = []
var timeline = frames.enumerated().map { poseFrame($0.element, Double($0.offset) / fps) }
if let last = frames.last {  // hold the final pose so a follow-through still in progress can finish
    for k in 1...Int(fps * 1.5) { timeline.append(poseFrame(last, Double(frames.count - 1 + k) / fps)) }
}
for pf in timeline {
    guard let m = analyzer.process(pf) else { continue }
    let r = evaluator.evaluate(m)
    let flaws = r.areas.filter { a in
        a.grade == .needsWork && !(a.area == .arc && a.value > evaluator.thresholds.arcOK.upperBound)
    }.compactMap { flawFor[$0.area] }
    shots.append([
        "feedback": [r.cue],
        "flaws": flaws,
        "busk": [
            "score": r.score,
            "focus": r.focus?.rawValue ?? NSNull(),
            "areas": r.areas.map { ["area": $0.area.rawValue, "grade": $0.grade.rawValue, "value": $0.value] },
        ] as [String: Any],
    ])
}
let doc: [String: Any] = ["shots": shots, "pose_source": "benchmark-keypoints", "analyzer": "busk ShotAnalyzer+FormEvaluator"]
let out = try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
try out.write(to: URL(fileURLWithPath: output))
