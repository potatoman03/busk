#!/usr/bin/env swift
// Runs Apple Vision body pose on a video on macOS and writes a `busk-bench-keypoints/1` sidecar.
// The iOS Simulator ships without Vision's body pose model, so `-videoPath` in the simulator replays this sidecar
// (CLIP.keypoints.json next to the clip) in sync with the video; on a device Vision runs live instead.
// It runs `busk-analyze --save-keypoints`, so the sidecar holds the same tracked shooter the analyzer coaches
// (not whoever is biggest in frame), with letterbox bars cropped.
// Usage: swift scripts/vision-keypoints.swift CLIP.mp4 [--handedness right|left] [--view side|front] [--output OUT.json]
import Foundation

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
let output = outputArg ?? url.deletingPathExtension().appendingPathExtension("keypoints.json").path
let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

let run = Process()
run.executableURL = URL(fileURLWithPath: "/usr/bin/env")
run.currentDirectoryURL = repo
run.arguments = ["swift", "run", "-c", "release", "busk-analyze", "--video", url.path, "--handedness", handedness,
                 "--view", view, "--output", NSTemporaryDirectory() + "busk-analyze-out.json", "--save-keypoints", output]
try run.run()
run.waitUntilExit()
guard run.terminationStatus == 0 else { exit(run.terminationStatus) }
print(output)
