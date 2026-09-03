// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexModelManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexModelManager", targets: ["CodexModelManager"]),
    ],
    targets: [
        .executableTarget(name: "CodexModelManager"),
        .testTarget(
            name: "CodexModelManagerTests",
            dependencies: ["CodexModelManager"]
        ),
    ]
)
