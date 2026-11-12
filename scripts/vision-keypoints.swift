#!/usr/bin/env swift
// Runs Apple Vision body pose on a video on macOS and writes a `busk-bench-keypoints/1` sidecar.
// The iOS Simulator ships without Vision's body pose model, so `-videoPath` in the simulator replays this sidecar
// (CLIP.keypoints.json next to the clip) in sync with the video; on a device Vision runs live instead.
// Usage: swift scripts/vision-keypoints.swift CLIP.mp4 [--handedness right|left] [--view side|front] [--output OUT.json]
import AVFoundation
import Foundation
import Vision

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...(i + 1)) }
    return args[i + 1]
}
let handedness = option("--handedness") ?? "right"
let view = option("--view") ?? "side"
let outputArg = option("--output")
guard let input = args.first else {
    FileHandle.standardError.write(Data("usage: vision-keypoints.swift CLIP.mp4 [--handedness right|left] [--view side|front] [--output OUT.json]\n".utf8))
    exit(64)
}
let url = URL(fileURLWithPath: input)
let output = outputArg.map { URL(fileURLWithPath: $0) }
    ?? url.deletingPathExtension().appendingPathExtension("keypoints.json")

let names: [VNHumanBodyPoseObservation.JointName: String] = [
    .nose: "nose", .neck: "neck", .root: "root",
    .leftShoulder: "left_shoulder", .rightShoulder: "right_shoulder",
    .leftElbow: "left_elbow", .rightElbow: "right_elbow",
    .leftWrist: "left_wrist", .rightWrist: "right_wrist",
    .leftHip: "left_hip", .rightHip: "right_hip",
    .leftKnee: "left_knee", .rightKnee: "right_knee",
    .leftAnkle: "left_ankle", .rightAnkle: "right_ankle",
]

func orientation(_ t: CGAffineTransform) -> CGImagePropertyOrientation {
    switch (t.a, t.b, t.c, t.d) {
    case (0, 1, -1, 0): return .right
    case (0, -1, 1, 0): return .left
    case (-1, 0, 0, -1): return .down
    default: return .up
    }
}

let asset = AVURLAsset(url: url)
guard let track = asset.tracks(withMediaType: .video).first, let reader = try? AVAssetReader(asset: asset) else {
    FileHandle.standardError.write(Data("cannot read video \(input)\n".utf8)); exit(1)
}
let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
reader.add(out)
reader.startReading()
let size = track.naturalSize.applying(track.preferredTransform)
let fps = Double(track.nominalFrameRate > 0 ? track.nominalFrameRate : 30)
let orient = orientation(track.preferredTransform)
let request = VNDetectHumanBodyPoseRequest()

var frames: [[String: Any]] = []
var detected = 0
while let sample = out.copyNextSampleBuffer() {
    guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
    let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
    try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: orient).perform([request])
    var joints: [String: [Double]] = [:]
    let area: (VNHumanBodyPoseObservation) -> CGFloat = { o in
        let pts = ((try? o.recognizedPoints(.all)) ?? [:]).values.filter { $0.confidence > 0.3 }
        guard let x0 = pts.map(\.location.x).min(), let x1 = pts.map(\.location.x).max(),
              let y0 = pts.map(\.location.y).min(), let y1 = pts.map(\.location.y).max() else { return 0 }
        return (x1 - x0) * (y1 - y0)
    }
    if let o = (request.results ?? []).max(by: { area($0) < area($1) }), let pts = try? o.recognizedPoints(.all) {
        for (name, key) in names {
            guard let p = pts[name], p.confidence > 0.3 else { continue }
            joints[key] = [Double(p.location.x), Double(1 - p.location.y)]
        }
        if !joints.isEmpty { detected += 1 }
    }
    frames.append(["t": t, "joints": joints])
}
let doc: [String: Any] = [
    "format": "busk-bench-keypoints/1", "source": "apple-vision", "fps": fps,
    "width": Double(abs(size.width)), "height": Double(abs(size.height)),
    "view": view, "handedness": handedness, "frames": frames,
]
try JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys]).write(to: output)
print("\(output.path): \(frames.count) frames, body found in \(detected)")
