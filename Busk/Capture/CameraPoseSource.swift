import AVFoundation
import UIKit
import Vision

/// Rear camera + Vision body pose, fully on device.
final class CameraPoseSource: NSObject, PoseSource {
    var onFrame: ((PoseFrame) -> Void)?
    let isDemo = false
    private(set) var aspectRatio: CGFloat = 9.0 / 16.0

    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "busk.camera", qos: .userInitiated)
    private let request = VNDetectHumanBodyPoseRequest()
    private var configured = false
    private var rotationAngle: CGFloat = 90

    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start() {
        videoQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured { self.configure() }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        videoQueue.async { [weak self] in
            if self?.session.isRunning == true { self?.session.stopRunning() }
        }
    }

    /// Keeps the delivered buffers upright for the current interface orientation.
    func setRotation(_ angle: CGFloat) {
        videoQueue.async { [weak self] in
            guard let self else { return }
            self.rotationAngle = angle
            if let c = self.output.connection(with: .video), c.isVideoRotationAngleSupported(angle) {
                c.videoRotationAngle = angle
            }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(output) { session.addOutput(output) }
        if let c = output.connection(with: .video), c.isVideoRotationAngleSupported(rotationAngle) {
            c.videoRotationAngle = rotationAngle
        }
        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        device.unlockForConfiguration()
        session.commitConfiguration()
        configured = true
    }
}

extension CameraPoseSource: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let w = CGFloat(CVPixelBufferGetWidth(pixelBuffer)), h = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([request])
        guard let observation = (request.results ?? []).max(by: { area($0) < area($1) }) else { return }
        let frame = PoseFrame(timestamp: ts, joints: Self.joints(from: observation))
        let ratio = h > 0 ? w / h : aspectRatio
        DispatchQueue.main.async { [weak self] in
            self?.aspectRatio = ratio
            self?.onFrame?(frame)
        }
    }

    private func area(_ o: VNHumanBodyPoseObservation) -> CGFloat {
        guard let pts = try? o.recognizedPoints(.all).values.filter({ $0.confidence > 0.3 }), !pts.isEmpty else { return 0 }
        let xs = pts.map(\.location.x), ys = pts.map(\.location.y)
        return (xs.max()! - xs.min()!) * (ys.max()! - ys.min()!)
    }

    static let mapping: [VNHumanBodyPoseObservation.JointName: Joint] = [
        .nose: .nose, .neck: .neck,
        .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
        .leftElbow: .leftElbow, .rightElbow: .rightElbow,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist,
        .leftHip: .leftHip, .rightHip: .rightHip,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee,
        .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
    ]

    static func joints(from o: VNHumanBodyPoseObservation) -> [Joint: CGPoint] {
        guard let points = try? o.recognizedPoints(.all) else { return [:] }
        var out: [Joint: CGPoint] = [:]
        for (name, joint) in mapping {
            guard let p = points[name], p.confidence > 0.3 else { continue }
            out[joint] = CGPoint(x: p.location.x, y: 1 - p.location.y)
        }
        return out
    }
}
