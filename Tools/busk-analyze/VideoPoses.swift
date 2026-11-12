import AVFoundation
import CoreGraphics
import ImageIO
import Vision

/// Reads a video file frame by frame and runs Apple Vision body-pose detection on each frame.
enum VideoPoses {
    static func read(_ url: URL, handedness: Handedness) throws -> [PoseFrame] {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { throw Failure("no video track in \(url.path)") }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        guard reader.startReading() else { throw Failure("cannot decode \(url.path): \(reader.error?.localizedDescription ?? "")") }

        let (orientation, rotated) = orientationOf(track.preferredTransform)
        let size = track.naturalSize
        let aspect = rotated ? size.height / size.width : size.width / size.height
        let request = VNDetectHumanBodyPoseRequest()
        var candidates: [(t: TimeInterval, people: [[Joint: CGPoint]])] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: orientation).perform([request])
            candidates.append((t, (request.results ?? []).map { VisionPose.joints(from: $0) }.filter { $0.count >= 4 }))
        }
        let frames = followShooter(candidates, handedness: handedness).map { PoseFrame(timestamp: $0.t, joints: $0.joints, aspect: aspect) }
        if reader.status == .failed { throw Failure("decode failed: \(reader.error?.localizedDescription ?? "")") }
        return frames
    }

    /// Picks the shooter out of everyone Vision sees: people are linked frame to frame into tracks by position,
    /// and the shooter is the track whose shooting hand goes from below the shoulder to straight up above the head.
    /// Among those (or among everyone, if nobody shoots) the biggest, longest-visible person wins.
    static func followShooter(_ frames: [(t: TimeInterval, people: [[Joint: CGPoint]])], handedness: Handedness)
        -> [(t: TimeInterval, joints: [Joint: CGPoint])] {
        func center(_ j: [Joint: CGPoint]) -> CGPoint {
            CGPoint(x: j.values.map(\.x).reduce(0, +) / CGFloat(j.count), y: j.values.map(\.y).reduce(0, +) / CGFloat(j.count))
        }
        func size(_ j: [Joint: CGPoint]) -> Double {
            let ys = j.values.map(\.y)
            return Double(ys.max()! - ys.min()!)
        }
        struct Track { var frames: [Int: [Joint: CGPoint]] = [:]; var last: CGPoint; var lastIndex: Int }
        var tracks: [Track] = []
        for (i, f) in frames.enumerated() {
            var taken = Set<Int>()
            for p in f.people.sorted(by: { size($0) > size($1) }) {
                let c = center(p)
                let match = tracks.indices
                    .filter { !taken.contains($0) && i - tracks[$0].lastIndex <= 15 && Geometry.distance(tracks[$0].last, c) < 0.08 }
                    .min { Geometry.distance(tracks[$0].last, c) < Geometry.distance(tracks[$1].last, c) }
                if let k = match {
                    tracks[k].frames[i] = p; tracks[k].last = c; tracks[k].lastIndex = i; taken.insert(k)
                } else {
                    tracks.append(Track(frames: [i: p], last: c, lastIndex: i)); taken.insert(tracks.count - 1)
                }
            }
        }
        func shoots(_ t: Track) -> Bool {
            var wasLow = false
            for i in t.frames.keys.sorted() {
                let j = t.frames[i]!
                guard let s = j[handedness.shoulder], let w = j[handedness.wrist] else { continue }
                if w.y > s.y { wasLow = true }
                if wasLow, let e = j[handedness.elbow], let head = j[.nose] ?? j[.neck], w.y < head.y,
                   Geometry.angle(s, e, w) > 140 { return true }
            }
            return false
        }
        func weight(_ t: Track) -> Double { t.frames.values.map(size).reduce(0, +) }
        let shooters = tracks.filter { $0.frames.count >= 10 && shoots($0) }
        let pick = (shooters.isEmpty ? tracks : shooters).max { weight($0) < weight($1) }
        return frames.enumerated().map { i, f in (f.t, pick?.frames[i] ?? [:]) }
    }

    private static func orientationOf(_ t: CGAffineTransform) -> (CGImagePropertyOrientation, Bool) {
        switch (t.a, t.b, t.c, t.d) {
        case (0, 1, -1, 0): return (.right, true)
        case (0, -1, 1, 0): return (.left, true)
        case (-1, 0, 0, -1): return (.down, false)
        default: return (.up, false)
        }
    }
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}
