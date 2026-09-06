// swift-tools-version: 6.3
// ws-cli — a multi-repo workspace helper, invoked as `ws`.

import PackageDescription

let package = Package(
    name: "ws-cli",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        // Thin executable: wires ArgumentParser to WorkspaceKit and nothing else.
        .executableTarget(
            name: "ws",
            dependencies: [
                "WorkspaceKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // All the logic lives here. No ArgumentParser import in this target.
        .target(name: "WorkspaceKit"),
    ],
    swiftLanguageModes: [.v6]
)
