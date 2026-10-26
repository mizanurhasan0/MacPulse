// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacPulse",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacPulse", targets: ["MacPulse"])
    ],
    targets: [
        .executableTarget(name: "MacPulse"),
        .testTarget(name: "MacPulseTests", dependencies: ["MacPulse"])
    ]
)
