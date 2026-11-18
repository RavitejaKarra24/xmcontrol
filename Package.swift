// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "sony_for_mac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "sony_for_mac",
            path: "Sources/sony_for_mac",
            linkerSettings: [
                .linkedFramework("IOBluetooth")
            ]
        ),
        .testTarget(name: "sony_for_macTests", dependencies: ["sony_for_mac"])
    ]
)
