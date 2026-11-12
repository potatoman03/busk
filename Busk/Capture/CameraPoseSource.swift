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
    private let detector = VisionPoseDetector()
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
        guard let joints = detector.joints(in: pixelBuffer) else { return }
        let frame = PoseFrame(timestamp: ts, joints: joints)
        let ratio = h > 0 ? w / h : aspectRatio
        DispatchQueue.main.async { [weak self] in
            self?.aspectRatio = ratio
            self?.onFrame?(frame)
        }
    }

}
