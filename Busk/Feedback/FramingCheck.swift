import CoreGraphics

/// Is the whole player in the shot? Checked before the first shot so the coach can say how to fix the camera.
struct FramingCheck: Equatable, Sendable {
    var body: Bool
    var head: Bool
    var arm: Bool
    var feet: Bool
    var centred: Bool

    var isGood: Bool { body && head && arm && feet && centred }

    init(frame: PoseFrame, handedness: Handedness) {
        // Vision points run 0...1 with y = 0 at the top of the image.
        let edge: CGFloat = 0.03
        func inside(_ p: CGPoint?) -> Bool { p.map { $0.y > edge && $0.y < 1 - edge } ?? false }
        body = !frame.joints.isEmpty
        head = inside(frame[.nose])
        arm = [handedness.shoulder, handedness.elbow, handedness.wrist].allSatisfy { frame[$0] != nil }
        feet = inside(frame[.leftAnkle]) || inside(frame[.rightAnkle])
        let hips = [frame[.leftHip], frame[.rightHip], frame[.root]].compactMap { $0 }
        centred = hips.isEmpty ? body : hips.allSatisfy { (0.12...0.88).contains($0.x) }
    }

    /// What to tell the player, most important first; nil when framing is good.
    var advice: String? {
        if !body { return "Step in front of the camera, 3 to 4 metres away" }
        if !feet && !head { return "Step back. Busk needs you head to feet" }
        if !feet { return "Busk can't see your feet. Step back or tilt the phone down" }
        if !head { return "Busk can't see your head. Step back or tilt the phone up" }
        if !arm { return "Busk can't see your shooting arm. Turn a little toward the phone" }
        if !centred { return "Move to the middle of the picture" }
        return nil
    }
}
