// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "HiLinkMessages",
    platforms: [.macOS("26.0")],
    dependencies: [
        // Generates Swift types for the stick's API from Sources/HiLinkMessages/openapi.yaml at build time.
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "HiLinkMessages",
            dependencies: [.product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")],
            path: "Sources/HiLinkMessages",
            plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
        ),
        .testTarget(name: "HiLinkMessagesTests", dependencies: ["HiLinkMessages"]),
    ]
)
