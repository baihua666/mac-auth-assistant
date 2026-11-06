// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacAuthAssistant",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MacAuthAssistant", targets: ["MacAuthAssistant"])],
    targets: [
        .target(name: "AuthCore"),
        .executableTarget(name: "MacAuthAssistant", dependencies: ["AuthCore"]),
        .testTarget(name: "AuthCoreTests", dependencies: ["AuthCore"]),
        .testTarget(name: "MacAuthAssistantTests", dependencies: ["MacAuthAssistant", "AuthCore"])
    ]
)
