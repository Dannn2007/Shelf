// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shelf",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Shelf",
            path: "Sources/Shelf",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
