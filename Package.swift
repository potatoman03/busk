// swift-tools-version:5.9
import PackageDescription

// `busk-analyze`: runs busk's on-device form analysis (Apple Vision pose -> ShotAnalyzer -> FormEvaluator)
// on a video file, for the shooting-feedback benchmark. The iOS app itself builds from project.yml.
let package = Package(
    name: "busk-analyze",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "busk-analyze",
            path: ".",
            sources: [
                "Busk/Models/Pose.swift",
                "Busk/Analysis/ShotAnalyzer.swift",
                "Busk/Analysis/FormEvaluator.swift",
                "Busk/Capture/VisionPose.swift",
                    "Busk/Capture/ShooterTracker.swift",
                "Tools/busk-analyze",
            ]
        ),
    ]
)
