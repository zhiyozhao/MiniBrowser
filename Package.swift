// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiniBrowser",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MiniBrowserCore"),
        .executableTarget(
            name: "MiniBrowser",
            dependencies: ["MiniBrowserCore"]
        ),
        .testTarget(
            name: "MiniBrowserCoreTests",
            dependencies: ["MiniBrowserCore"]
        )
    ]
)
