// swift-tools-version:5.9
import PackageDescription

// Wraps busk's own ShotAnalyzer + FormEvaluator (copied from Busk/ by run.sh) in the benchmark's CLI contract.
var deps: [Target.Dependency] = []
var targets: [Target] = []
#if os(Linux)
targets.append(.target(name: "CoreGraphics", path: "Sources/CoreGraphicsShim"))
deps.append("CoreGraphics")
#endif
targets.append(.executableTarget(name: "busk-analyze", dependencies: deps, path: "Sources/busk-analyze"))
let package = Package(name: "busk-analyze", targets: targets)
