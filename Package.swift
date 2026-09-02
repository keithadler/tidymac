// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TidyMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TidyMac",
            path: "Sources/TidyMac"
        )
    ]
)
