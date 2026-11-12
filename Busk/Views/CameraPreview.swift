import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let source: CameraPoseSource

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        weak var source: CameraPoseSource?

        override func layoutSubviews() {
            super.layoutSubviews()
            if let angle = source?.previewRotationAngle { CameraPoseSource.apply(angle, to: previewLayer.connection) }
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = source.session
        v.previewLayer.videoGravity = .resizeAspectFill
        v.source = source
        source.followRotation(of: v.previewLayer)
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
