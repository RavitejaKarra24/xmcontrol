// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "XMControl",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "XMControl",
            path: "Sources/XMControl",
            linkerSettings: [
                .linkedFramework("IOBluetooth")
            ]
        ),
        .testTarget(name: "XMControlTests", dependencies: ["XMControl"])
    ]
)
