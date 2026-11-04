// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InterviewAI",
    platforms: [.macOS(.v14)],
    dependencies: [
        // WhisperKit (MIT, Argmax): on-device Whisper transcription, the
        // same engine family Handy uses through whisper.cpp. Only the
        // Whisper engine links it; Apple Speech stays dependency-free.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
        // FluidAudio (Apache-2.0, FluidInference): Core ML audio models on
        // the Neural Engine. It carries Parakeet Ultra, Moondream's
        // post-trained Parakeet v3, the default engine.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.7"),
    ],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "InterviewAIKit", dependencies: [
            .product(name: "WhisperKit", package: "argmax-oss-swift"),
            .product(name: "FluidAudio", package: "FluidAudio"),
        ]),
        .executableTarget(
            name: "InterviewAI",
            dependencies: ["InterviewAIKit"],
            // Excluded from the build, but Xcode uses this Info.plist for
            // the app product (the privacy usage descriptions live there).
            // The installed app from build.sh uses Info.plist.in instead.
            exclude: ["Info.plist"],
            // The flat icon, copied into the app bundle. The Liquid Glass
            // variant comes from Icon/AppIcon.icon on the build.sh route.
            resources: [.copy("AppIcon.icns")],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "InterviewAIKitTests", dependencies: ["InterviewAIKit"]),
    ]
)
