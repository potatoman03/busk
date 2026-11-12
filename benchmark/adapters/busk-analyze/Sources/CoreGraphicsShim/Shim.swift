// On Linux, CGPoint and CGFloat come from Foundation.
@_exported import Foundation

public struct CGVector: Equatable, Sendable {
    public var dx: CGFloat
    public var dy: CGFloat
    public init(dx: CGFloat, dy: CGFloat) { self.dx = dx; self.dy = dy }
    public init(dx: Double, dy: Double) { self.dx = CGFloat(dx); self.dy = CGFloat(dy) }
    public static let zero = CGVector(dx: 0.0, dy: 0.0)
}
