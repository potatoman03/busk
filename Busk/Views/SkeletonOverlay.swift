import SwiftUI

struct SkeletonOverlay: View {
    let pose: PoseFrame?
    let handedness: Handedness
    let aspectRatio: CGFloat
    let phase: ShotPhase
    /// Aspect-fill to line up with a full-screen camera preview; otherwise fit so the whole body stays visible.
    var fill = true

    private static let bones: [(Joint, Joint)] = [
        (.nose, .neck), (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip), (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    var body: some View {
        Canvas { ctx, size in
            guard let pose else { return }
            let map = Self.mapper(size: size, aspectRatio: aspectRatio, fill: fill)
            let shooting: Set<Joint> = [handedness.shoulder, handedness.elbow, handedness.wrist]
            let accent = phase == .waiting ? Color.white : Theme.orange
            for (a, b) in Self.bones {
                guard let pa = pose[a], let pb = pose[b] else { continue }
                var path = Path()
                path.move(to: map(pa))
                path.addLine(to: map(pb))
                let hot = shooting.contains(a) && shooting.contains(b)
                ctx.stroke(path, with: .color(hot ? accent : .white.opacity(0.75)),
                           style: StrokeStyle(lineWidth: hot ? 6 : 3.5, lineCap: .round))
            }
            for (joint, p) in pose.joints {
                let c = map(p)
                let r: CGFloat = shooting.contains(joint) ? 7 : 4.5
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(shooting.contains(joint) ? accent : .white))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Maps normalized image points into the view, matching aspect-fill or aspect-fit.
    static func mapper(size: CGSize, aspectRatio: CGFloat, fill: Bool = true) -> (CGPoint) -> CGPoint {
        let ar = max(aspectRatio, 0.01)
        let viewAR = size.width / max(size.height, 1)
        let w: CGFloat, h: CGFloat
        if (viewAR > ar) == fill { w = size.width; h = size.width / ar } else { h = size.height; w = size.height * ar }
        let ox = (size.width - w) / 2, oy = (size.height - h) / 2
        return { CGPoint(x: ox + $0.x * w, y: oy + $0.y * h) }
    }
}
