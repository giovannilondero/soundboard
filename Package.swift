// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "soundboard",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "soundboard",
            path: "Sources/soundboard",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
            ]
        ),
    ]
)
