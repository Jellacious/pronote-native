// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PronoteNative",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PronoteNative", targets: ["PronoteNative"])
    ],
    targets: [
        .executableTarget(
            name: "PronoteNative",
            path: "Sources/PronoteNative"
        )
    ]
)
