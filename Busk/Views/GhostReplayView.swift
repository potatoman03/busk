import SwiftUI

/// Slow-motion replay of the last shot with the session's best shot drawn over it as a translucent ghost.
struct GhostReplayView: View {
    let replay: ShotReplay
    let handedness: Handedness
    var onFinish: () -> Void

    static let speed = 0.35
    static let ghostColor = Color.cyan
    @State private var start = Date()

    private var duration: TimeInterval { (ShotReplay.before + ShotReplay.after) / Self.speed }

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation) { timeline in
                let t = min(timeline.date.timeIntervalSince(start) * Self.speed - ShotReplay.before, ShotReplay.after)
                VStack(spacing: 6) {
                    Canvas { ctx, size in draw(in: &ctx, size: size, at: t) }
                        .overlay(alignment: .top) {
                            if abs(t) < 0.07 {
                                Text("RELEASE").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.white, in: Capsule()).foregroundStyle(.black)
                                    .accessibilityIdentifier("ghostReplayRelease")
                            }
                        }
                    scrubber(t)
                }
            }
            header
        }
        .padding(12)
        .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.15)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onFinish)
        .task(id: replay.id) {
            start = Date()
            try? await Task.sleep(for: .seconds(duration + 0.8))
            if !Task.isCancelled { onFinish() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ghostReplay")
    }

    private var header: some View {
        HStack(spacing: 12) {
            legend(color: Theme.orange, text: "Shot \(replay.shot.number) · \(replay.shot.score)")
            if let ghost = replay.ghost {
                legend(color: Self.ghostColor.opacity(0.6), text: "Best · shot \(ghost.number) · \(ghost.score)")
            }
            Spacer(minLength: 0)
            if replay.isNewBest {
                Text(replay.ghost == nil ? "First shot" : "New best").font(.caption.bold()).foregroundStyle(.green)
            }
            Text(String(format: "%.2g×", Self.speed)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("ghostReplayLegend")
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text).font(.caption.bold()).lineLimit(1)
        }
    }

    private func scrubber(_ t: TimeInterval) -> some View {
        GeometryReader { geo in
            let span = ShotReplay.before + ShotReplay.after
            let x = { (s: TimeInterval) in geo.size.width * (s + ShotReplay.before) / span }
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(Theme.orange).frame(width: max(0, x(t)))
                Rectangle().fill(.white).frame(width: 2, height: 10).offset(x: x(0) - 1)
            }
        }
        .frame(height: 4)
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, at t: TimeInterval) {
        let b = replay.bounds.insetBy(dx: -max(replay.bounds.width, 0.05) * 0.12, dy: -max(replay.bounds.height, 0.05) * 0.08)
        let scale = min(size.width / max(b.width, 0.01), size.height / max(b.height, 0.01))
        let ox = (size.width - b.width * scale) / 2 - b.minX * scale
        let oy = (size.height - b.height * scale) / 2 - b.minY * scale
        let map = { (p: CGPoint) in CGPoint(x: ox + p.x * scale, y: oy + p.y * scale) }
        if let ghost = replay.ghost {
            drawTrail(ghost, upTo: t, in: &ctx, map: map, color: Self.ghostColor.opacity(0.5), dash: [6, 6])
            drawSkeleton(ghost.pose(at: t), in: &ctx, map: map, color: Self.ghostColor.opacity(0.45), arm: Self.ghostColor.opacity(0.6), width: 9)
        }
        drawTrail(replay.shot, upTo: t, in: &ctx, map: map, color: Theme.orange.opacity(0.7), dash: [])
        drawSkeleton(replay.shot.pose(at: t), in: &ctx, map: map, color: .white.opacity(0.85), arm: Theme.orange, width: 5)
    }

    private func drawSkeleton(_ pose: [Joint: CGPoint], in ctx: inout GraphicsContext, map: (CGPoint) -> CGPoint,
                              color: Color, arm: Color, width: CGFloat) {
        let shooting: Set<Joint> = [handedness.shoulder, handedness.elbow, handedness.wrist]
        for (a, b) in SkeletonOverlay.bones {
            guard let pa = pose[a], let pb = pose[b] else { continue }
            var path = Path()
            path.move(to: map(pa))
            path.addLine(to: map(pb))
            let hot = shooting.contains(a) && shooting.contains(b)
            ctx.stroke(path, with: .color(hot ? arm : color), style: StrokeStyle(lineWidth: hot ? width * 1.5 : width, lineCap: .round))
        }
        if let head = pose[.nose] {
            let c = map(head), r = width * 1.8
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
        }
    }

    /// The shooting wrist's path so far, so the set point and arc of the two shots can be compared.
    private func drawTrail(_ track: ShotReplay.Track, upTo t: TimeInterval, in ctx: inout GraphicsContext,
                           map: (CGPoint) -> CGPoint, color: Color, dash: [CGFloat]) {
        let points = zip(track.times, track.poses).filter { $0.0 <= t }.compactMap { $0.1[handedness.wrist] }
        guard points.count > 1 else { return }
        var path = Path()
        path.addLines(points.map(map))
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: dash))
    }
}
