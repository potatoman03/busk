import CoreGraphics
import CoreImage
import CoreVideo
import ImageIO

/// Finds the basketball in the shooter's hands, on device, without a model: in a small render of the area around the
/// hands, the ball is the round blob of saturated orange about a ball's size for the body in view, nearest the hands
/// (and, while it is being followed, nearest where it was a moment ago).
final class BallDetector {
    private let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false])
    private var last: (ball: Ball, t: TimeInterval)?
    /// Render pixels across the expected ball radius.
    private let pixelsPerRadius: CGFloat = 7

    func reset() { last = nil }

    func detect(in pixels: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up, joints: [Joint: CGPoint],
                at t: TimeInterval) -> Ball? {
        detect(in: CIImage(cvPixelBuffer: pixels).oriented(orientation), joints: joints, at: t) { area, s, w, h in
            Self.render(pixels, orientation: orientation, area: area, scale: s, width: w, height: h)
        }
    }

    /// `joints` and the result are in normalized top-left coordinates of `image`. `render` draws the area around the
    /// hands (top-left image coordinates) at a scale into RGBA rows; without it, or when it can't, Core Image does.
    func detect(in image: CIImage, joints: [Joint: CGPoint], at t: TimeInterval,
                render: ((CGRect, CGFloat, Int, Int) -> [UInt8]?)? = nil) -> Ball? {
        let ext = image.extent
        let W = ext.width, H = ext.height
        guard W > 0, H > 0 else { return nil }
        let px = { (p: CGPoint) in CGPoint(x: p.x * W, y: p.y * H) }
        let hands = [Joint.rightWrist, .leftWrist].compactMap { joints[$0] }.map(px)
        guard !hands.isEmpty else { return nil }
        // Body scale: shoulders to hips. A ball's radius is about a quarter of that.
        let mid = { (a: Joint, b: Joint) -> CGPoint? in
            guard let p = joints[a], let q = joints[b] else { return joints[a] ?? joints[b] }
            return CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
        }
        guard let top = joints[.neck] ?? mid(.leftShoulder, .rightShoulder),
              let bottom = joints[.root] ?? mid(.leftHip, .rightHip) else { return nil }
        let torso = Geometry.distance(px(top), px(bottom))
        guard torso > 8 else { return nil }
        let r0 = 0.24 * torso
        let recent = last.flatMap { t - $0.t >= 0 && t - $0.t < 0.25 ? px($0.ball.center) : nil }

        var area = CGRect.null
        for p in hands + [Joint.rightElbow, .leftElbow].compactMap({ joints[$0] }).map(px) + (recent.map { [$0] } ?? []) {
            area = area.union(CGRect(origin: p, size: .zero))
        }
        area = area.insetBy(dx: -3 * r0, dy: -3 * r0).intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard !area.isNull, area.width >= 4, area.height >= 4 else { return nil }

        let s = min(pixelsPerRadius / r0, 2)
        let w = Int((area.width * s).rounded(.up)), h = Int((area.height * s).rounded(.up))
        guard w >= 4, h >= 4, w * h <= 400 * 400 else { return nil }
        let rgba = render?(area, s, w, h) ?? {
            let crop = CGRect(x: ext.minX + area.minX, y: ext.minY + H - area.maxY, width: area.width, height: area.height)
            let small = image.cropped(to: crop)
                .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                .transformed(by: CGAffineTransform(scaleX: s, y: s))
            var rgba = [UInt8](repeating: 0, count: w * h * 4)
            // Core Image counts up from the bottom and the bitmap's first row is its top: line that row up with the
            // area's top edge, or every ball is found up to a render pixel too low.
            context.render(small, toBitmap: &rgba, rowBytes: w * 4,
                           bounds: CGRect(x: 0, y: area.height * s - CGFloat(h), width: CGFloat(w), height: CGFloat(h)),
                           format: .RGBA8, colorSpace: nil)
            return rgba
        }()

        // Skin or a tan wall touching the ball can pass the loosest orange test and merge with it into one bigger,
        // off-centre blob: stricter saturation splits them, and the roundest, best-sized blob of any pass wins. A hand
        // or forearm across the ball leaves a gap in it that pulls the blob's mean off centre, but not its outline:
        // the ball's centre is the middle of the blob's extent.
        let expected = r0 * s
        // A ball keeps its size from frame to frame: a blob much bigger than the one just followed has merged with skin
        // or the shirt next to it, and its box is off the ball.
        let followed = last.flatMap { t - $0.t >= 0 && t - $0.t < 0.25 ? $0.ball.radius * H * s : nil }
        let toImage = { (x: CGFloat, y: CGFloat) in CGPoint(x: area.minX + x / s, y: area.minY + y / s) }
        var found: [(score: Double, ball: Ball)] = []
        for saturation in Self.saturations {
            for b in Self.blobs(Self.orangeMask(rgba, width: w, height: h, saturation: saturation), width: w, height: h) {
                let (x0, x1, y0, y1) = Self.extent(of: b, width: w)
                let bw = CGFloat(x1 - x0 + 1), bh = CGFloat(y1 - y0 + 1)
                let radius = max(bw, bh) / 2
                let size = Double(radius / expected)
                let fill = Double(b.count) / (Double.pi * Double(radius * radius))
                guard size >= 0.45, size <= 2, fill >= 0.35, min(bw, bh) / max(bw, bh) >= 0.45 else { continue }
                if let followed, radius > 1.3 * followed { continue }
                let center = toImage(CGFloat(x0 + x1 + 1) / 2, CGFloat(y0 + y1 + 1) / 2)
                let reach = hands.map { Double(Geometry.distance($0, center) / r0) }.min()!
                guard reach <= 3 else { continue }
                var score = abs(log(size)) + 0.4 * reach - fill
                if let recent { score += 0.3 * Double(Geometry.distance(recent, center) / r0) }
                found.append((score, Ball(center: CGPoint(x: center.x / W, y: center.y / H), radius: radius / s / H)))
            }
        }
        let best = found.min { $0.score < $1.score }
        if let ball = best?.ball { last = (ball, t) }
        return best?.ball
    }

    /// The `area` of `pixels` (top-left coordinates of the oriented picture) at `s` render pixels per picture pixel,
    /// as RGBA rows, sampled and converted from YCbCr here rather than by Core Image: decoding a clip is exact, so
    /// the app in the simulator or on a phone and the benchmark on a Mac find the ball in the very same pixels.
    static func render(_ pixels: CVPixelBuffer, orientation: CGImagePropertyOrientation, area: CGRect, scale s: CGFloat,
                       width w: Int, height h: Int) -> [UInt8]? {
        let format = CVPixelBufferGetPixelFormatType(pixels)
        let split = format == kCVPixelFormatType_420YpCbCr8Planar || format == kCVPixelFormatType_420YpCbCr8PlanarFullRange
        let full = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || format == kCVPixelFormatType_420YpCbCr8PlanarFullRange
        let planar = split || full || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        guard planar || format == kCVPixelFormatType_32BGRA else { return nil }
        let bw = Double(CVPixelBufferGetWidth(pixels)), bh = Double(CVPixelBufferGetHeight(pixels))
        let toBuffer: (Double, Double) -> (Double, Double)
        switch orientation {
        case .up: toBuffer = { ($0, $1) }
        case .down: toBuffer = { (bw - $0, bh - $1) }
        case .right: toBuffer = { u, v in (v, bh - u) }
        case .left: toBuffer = { u, v in (bw - v, u) }
        default: return nil
        }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        struct Plane {
            let base: UnsafePointer<UInt8>, row: Int, width: Int, height: Int, stride: Int
            func sample(_ x: Double, _ y: Double, _ channel: Int) -> Double {
                let fx = min(max(x, 0), Double(width - 1)), fy = min(max(y, 0), Double(height - 1))
                let x0 = Int(fx), y0 = Int(fy), x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
                let ax = fx - Double(x0), ay = fy - Double(y0)
                let p = { (x: Int, y: Int) in Double(base[y * row + x * stride + channel]) }
                return (p(x0, y0) * (1 - ax) + p(x1, y0) * ax) * (1 - ay) + (p(x0, y1) * (1 - ax) + p(x1, y1) * ax) * ay
            }
        }
        func plane(_ i: Int, stride: Int) -> Plane? {
            let base = planar ? CVPixelBufferGetBaseAddressOfPlane(pixels, i) : CVPixelBufferGetBaseAddress(pixels)
            guard let base else { return nil }
            return Plane(base: UnsafePointer(base.assumingMemoryBound(to: UInt8.self)),
                         row: planar ? CVPixelBufferGetBytesPerRowOfPlane(pixels, i) : CVPixelBufferGetBytesPerRow(pixels),
                         width: planar ? CVPixelBufferGetWidthOfPlane(pixels, i) : Int(bw),
                         height: planar ? CVPixelBufferGetHeightOfPlane(pixels, i) : Int(bh), stride: stride)
        }
        guard let luma = plane(0, stride: planar ? 1 : 4), let cbPlane = planar ? plane(1, stride: split ? 1 : 2) : luma,
              let crPlane = split ? plane(2, stride: 1) : cbPlane else { return nil }
        let crChannel = split ? 0 : 1
        let matrix = CVBufferCopyAttachment(pixels, kCVImageBufferYCbCrMatrixKey, nil) as? String
        let (kr, kgb, kgr, kb) = matrix == (kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String)
            ? (1.402, 0.344136, 0.714136, 1.772) : (1.5748, 0.187324, 0.468124, 1.8556)
        let byte = { (v: Double) in UInt8(min(max(v.rounded(), 0), 255)) }
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let (px, py) = toBuffer(Double(area.minX) + (Double(x) + 0.5) / Double(s), Double(area.minY) + (Double(y) + 0.5) / Double(s))
                let i = 4 * (y * w + x)
                if planar {
                    var l = luma.sample(px - 0.5, py - 0.5, 0)
                    var cb = cbPlane.sample(px / 2 - 0.5, py / 2 - 0.5, 0) - 128, cr = crPlane.sample(px / 2 - 0.5, py / 2 - 0.5, crChannel) - 128
                    if !full { l = (l - 16) * 255 / 219; cb *= 255.0 / 224; cr *= 255.0 / 224 }
                    rgba[i] = byte(l + kr * cr); rgba[i + 1] = byte(l - kgb * cb - kgr * cr); rgba[i + 2] = byte(l + kb * cb)
                } else {
                    rgba[i] = byte(luma.sample(px - 0.5, py - 0.5, 2))
                    rgba[i + 1] = byte(luma.sample(px - 0.5, py - 0.5, 1))
                    rgba[i + 2] = byte(luma.sample(px - 0.5, py - 0.5, 0))
                }
            }
        }
        return rgba
    }

    /// Basketball orange: red the strongest channel, hue between a little past red and orange, clearly saturated
    /// (skin, wooden floors and sand-coloured courts are paler or yellower), neither black nor blown out.
    static let saturations = [38, 50, 62]

    static func orangeMask(_ rgba: [UInt8], width w: Int, height h: Int, saturation: Int = 38) -> [Bool] {
        var mask = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) {
            let r = Int(rgba[4 * i]), g = Int(rgba[4 * i + 1]), b = Int(rgba[4 * i + 2])
            let hi = max(r, g, b), lo = min(r, g, b), d = hi - lo
            guard hi == r, hi >= 40, d * 100 >= hi * saturation else { continue }
            let hue = 60 * Double(g - b) / Double(d)
            mask[i] = hue >= -15 && hue <= 32
        }
        return mask
    }

    struct Blob {
        var count = 0, sumX = 0, sumY = 0, minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        var pixels: [Int] = []
    }

    /// The blob's extent without the rows and columns where only a few stray pixels reach out of it: compression
    /// speckle in skin or a wall next to the ball can pass the orange test and join the ball across the one-pixel
    /// gap, stretching the box (and the centre taken from it) towards the head or the hands.
    static func extent(of b: Blob, width w: Int) -> (minX: Int, maxX: Int, minY: Int, maxY: Int) {
        var rows: [Int: Int] = [:], cols: [Int: Int] = [:]
        for i in b.pixels { rows[i / w, default: 0] += 1; cols[i % w, default: 0] += 1 }
        let span = { (counts: [Int: Int], lo: Int, hi: Int) -> (Int, Int) in
            let solid = counts.filter { 4 * $0.value >= counts.values.max()! }.keys
            return (solid.min() ?? lo, solid.max() ?? hi)
        }
        let (x0, x1) = span(cols, b.minX, b.maxX), (y0, y1) = span(rows, b.minY, b.maxY)
        return (x0, x1, y0, y1)
    }

    /// Connected orange regions. Neighbours are joined across a one-pixel gap, so the seams don't split the ball.
    static func blobs(_ mask: [Bool], width w: Int, height h: Int) -> [Blob] {
        var label = [Int32](repeating: -1, count: w * h)
        var out: [Blob] = []
        var stack: [Int] = []
        for start in 0..<(w * h) where mask[start] && label[start] < 0 {
            var blob = Blob()
            let id = Int32(out.count)
            label[start] = id
            stack.append(start)
            while let i = stack.popLast() {
                let x = i % w, y = i / w
                blob.count += 1; blob.sumX += x; blob.sumY += y; blob.pixels.append(i)
                blob.minX = min(blob.minX, x); blob.maxX = max(blob.maxX, x)
                blob.minY = min(blob.minY, y); blob.maxY = max(blob.maxY, y)
                for dy in -2...2 {
                    for dx in -2...2 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                        let j = ny * w + nx
                        if mask[j], label[j] < 0 { label[j] = id; stack.append(j) }
                    }
                }
            }
            out.append(blob)
        }
        return out
    }
}
