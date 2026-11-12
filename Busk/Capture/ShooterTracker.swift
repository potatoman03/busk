import CoreGraphics

/// Picks the shooter out of everyone Vision sees, frame by frame, for live sessions.
/// Stays on the person it is following (nearest to where they were), and switches to someone else only when
/// that person brings a hand above their shoulders while the followed person doesn't: the shooter lifting the ball,
/// not a bigger player standing closer to the camera.
final class ShooterTracker {
    private var center: CGPoint?
    private var size: CGFloat = 0
    private var missed = 0
    /// Frames without a match before the followed person is considered gone.
    var patience = 15

    func select(_ people: [[Joint: CGPoint]]) -> [Joint: CGPoint]? {
        let people = people.filter { $0.count >= 4 }
        guard !people.isEmpty else { return lost() }

        var followed: [Joint: CGPoint]?
        if let c = center {
            let near = people.min { Geometry.distance(Self.center($0), c) < Geometry.distance(Self.center($1), c) }!
            let ratio = Self.size(near) / max(size, 0.01)
            if Geometry.distance(Self.center(near), c) < Double(max(size, 0.1)) * 0.3, ratio > 0.6, ratio < 1.6 { followed = near }
        }
        // Someone in the stands with a hand up isn't the shooter: a raiser has to be about as big as the followed person
        // and stand on the same floor (feet below the followed person's head).
        let raiser = people.filter { p in
            guard Self.handRaised(p) else { return false }
            guard let f = followed else { return true }
            return Self.size(p) >= Self.size(f) * 0.6 && Self.bounds(p).maxY > Self.bounds(f).minY
        }.max { Self.size($0) < Self.size($1) }
        let pick: [Joint: CGPoint]?
        if let f = followed {
            pick = raiser != nil && !Self.handRaised(f) ? raiser : f
        } else if center != nil, missed + 1 < patience {
            return lost()
        } else {
            pick = raiser ?? people.max { Self.size($0) < Self.size($1) }
        }
        guard let chosen = pick else { return lost() }
        center = Self.center(chosen)
        size = Self.size(chosen)
        missed = 0
        return chosen
    }

    func reset() {
        center = nil
        missed = 0
    }

    private func lost() -> [Joint: CGPoint]? {
        missed += 1
        if missed >= patience { center = nil }
        return nil
    }

    static func handRaised(_ j: [Joint: CGPoint]) -> Bool {
        let shoulders = [j[.leftShoulder], j[.rightShoulder], j[.neck]].compactMap { $0?.y }
        guard let top = shoulders.min() else { return false }
        return [j[.leftWrist], j[.rightWrist]].contains { ($0?.y ?? 1) < top }
    }

    static func center(_ j: [Joint: CGPoint]) -> CGPoint {
        CGPoint(x: j.values.map(\.x).reduce(0, +) / CGFloat(j.count), y: j.values.map(\.y).reduce(0, +) / CGFloat(j.count))
    }

    static func size(_ j: [Joint: CGPoint]) -> CGFloat { bounds(j).height }

    static func bounds(_ j: [Joint: CGPoint]) -> CGRect {
        let xs = j.values.map(\.x), ys = j.values.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return .zero }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
