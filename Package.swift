// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TracklessTelemetry",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "TracklessTelemetry", targets: ["TracklessTelemetry"]),
    ],
    targets: [
        .target(name: "TracklessTelemetry", path: "Sources/TracklessTelemetry"),
        .testTarget(name: "TracklessTelemetryTests", dependencies: ["TracklessTelemetry"]),
    ]
)
