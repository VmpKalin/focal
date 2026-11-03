// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Focal",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Focal",
            path: "Sources/Focal",
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ]
)
