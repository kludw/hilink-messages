// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "HiLinkMessages",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "HiLinkMessages", path: "Sources/HiLinkMessages")
    ]
)
