// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Bose-Mute-Microphone",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BoseMuteMicrophone", targets: ["BoseMuteMicrophone"]),
        .executable(name: "bose-mute-diag", targets: ["bose-mute-diag"]),
    ],
    targets: [
        .target(name: "BoseMuteCore"),
        .executableTarget(name: "BoseMuteMicrophone", dependencies: ["BoseMuteCore"]),
        .executableTarget(name: "bose-mute-diag", dependencies: ["BoseMuteCore"]),
        .testTarget(name: "BoseMuteCoreTests", dependencies: ["BoseMuteCore"]),
    ]
)
