import AVFoundation
import CoreImage
import CoreGraphics
import ImageIO
import Vision

/// Reads a video file frame by frame and runs Apple Vision body-pose detection on each frame.
enum VideoPoses {
    static func read(_ url: URL, handedness: Handedness, live: Bool = false) throws -> [PoseFrame] {
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
        var content: CGRect?
        while let sample = output.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if candidates.isEmpty, orientation == .up { content = contentBounds(pixels) }
            var people: [[Joint: CGPoint]]
            if let r = content {
                // Letterboxed footage: run Vision on the picture only, so the shooter fills more of its input.
                let w = CGFloat(CVPixelBufferGetWidth(pixels)), h = CGFloat(CVPixelBufferGetHeight(pixels))
                let ciRect = CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
                let image = CIImage(cvPixelBuffer: pixels).cropped(to: ciRect)
                    .transformed(by: CGAffineTransform(translationX: -ciRect.minX, y: -ciRect.minY))
                try? VNImageRequestHandler(ciImage: image).perform([request])
                people = (request.results ?? []).map { VisionPose.joints(from: $0).mapValues {
                    CGPoint(x: (r.minX + $0.x * r.width) / w, y: (r.minY + $0.y * r.height) / h)
                } }
            } else {
                try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: orientation).perform([request])
                people = (request.results ?? []).map { VisionPose.joints(from: $0) }
            }
            candidates.append((t, people.filter { $0.count >= 4 }))
        }
        if reader.status == .failed { throw Failure("decode failed: \(reader.error?.localizedDescription ?? "")") }
        let tracker = ShooterTracker()
        let followed: [(i: Int, t: TimeInterval, joints: [Joint: CGPoint])] = live
            ? candidates.enumerated().compactMap { i, c in tracker.select(c.people).map { (i, c.t, $0) } }
            : followShooter(candidates, handedness: handedness).enumerated().map { ($0, $1.t, $1.joints) }
        let balls = try findBalls(url, orientation: orientation, joints: Dictionary(followed.map { ($0.i, $0.joints) }) { a, _ in a })
        return followed.map { PoseFrame(timestamp: $0.t, joints: $0.joints, aspect: aspect, ball: balls[$0.i]) }
    }

    /// Second pass over the video: the ball near the followed shooter's hands in each frame, as the app's
    /// `BallDetector` finds it live.
    static func findBalls(_ url: URL, orientation: CGImagePropertyOrientation, joints: [Int: [Joint: CGPoint]]) throws -> [Int: Ball] {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return [:] }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        guard reader.startReading() else { return [:] }
        let detector = BallDetector()
        var balls: [Int: Ball] = [:]
        var i = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            if let j = joints[i], !j.isEmpty {
                let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                balls[i] = detector.detect(in: pixels, orientation: orientation, joints: j, at: t)
            }
            i += 1
        }
        return balls
    }

    /// The picture inside black letterbox / pillarbox bars (top-left origin, pixels), or nil when there are no bars.
    static func contentBounds(_ pixels: CVPixelBuffer) -> CGRect? {
        guard CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let w = CVPixelBufferGetWidth(pixels), h = CVPixelBufferGetHeight(pixels), row = CVPixelBufferGetBytesPerRow(pixels)
        func lit(_ x: Int, _ y: Int) -> Bool {
            let p = base + y * row + x * 4
            return max(p[0], p[1], p[2]) > 24
        }
        let step = 4
        let cols = stride(from: 0, to: w, by: 1).filter { x in stride(from: 0, to: h, by: step).contains { lit(x, $0) } }
        let rows = stride(from: 0, to: h, by: 1).filter { y in stride(from: 0, to: w, by: step).contains { lit($0, y) } }
        guard let x0 = cols.first, let x1 = cols.last, let y0 = rows.first, let y1 = rows.last else { return nil }
        let r = CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
        return r.width < CGFloat(w) * 0.9 || r.height < CGFloat(h) * 0.9 ? r : nil
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
