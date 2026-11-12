import CoreImage
import XCTest
@testable import Busk

final class BallDetectorTests: XCTestCase {
    /// A grey frame with an orange ball (and a skin-coloured hand blob) drawn at `ball`, top-left normalized.
    private func image(ball: CGPoint, radius: CGFloat, size: CGSize = CGSize(width: 640, height: 480)) -> CIImage {
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.55, green: 0.55, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        let c = CGPoint(x: ball.x * size.width, y: (1 - ball.y) * size.height)
        let r = radius * size.height
        ctx.setFillColor(CGColor(red: 0.87, green: 0.43, blue: 0.14, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.setFillColor(CGColor(red: 0.85, green: 0.7, blue: 0.6, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: c.x + r * 0.6, y: c.y - r * 1.4, width: r, height: r))
        return CIImage(cgImage: ctx.makeImage()!)
    }

    private let joints: [Joint: CGPoint] = [
        .neck: CGPoint(x: 0.5, y: 0.3), .root: CGPoint(x: 0.5, y: 0.6),
        .rightShoulder: CGPoint(x: 0.45, y: 0.3), .rightElbow: CGPoint(x: 0.42, y: 0.4), .rightWrist: CGPoint(x: 0.45, y: 0.33),
    ]

    func testFindsTheBallInTheHand() throws {
        let ball = try XCTUnwrap(BallDetector().detect(in: image(ball: CGPoint(x: 0.46, y: 0.27), radius: 0.07), joints: joints, at: 0))
        XCTAssertEqual(ball.center.x, 0.46, accuracy: 0.01)
        XCTAssertEqual(ball.center.y, 0.27, accuracy: 0.01)
        XCTAssertEqual(ball.radius, 0.07, accuracy: 0.015)
    }

    func testIgnoresABallFarFromTheHands() {
        XCTAssertNil(BallDetector().detect(in: image(ball: CGPoint(x: 0.9, y: 0.85), radius: 0.07), joints: joints, at: 0))
    }

    func testIgnoresAnOrangeBlobTheWrongSizeForTheBody() {
        XCTAssertNil(BallDetector().detect(in: image(ball: CGPoint(x: 0.46, y: 0.27), radius: 0.015), joints: joints, at: 0))
    }
}
