// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Daylight",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Daylight", targets: ["Daylight"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4")
    ],
    targets: [
        .executableTarget(
            name: "Daylight",
            dependencies: ["Sparkle"],
            path: "Sources/Daylight"
        ),
        .testTarget(
            name: "DaylightTests",
            dependencies: ["Daylight"],
            path: "Tests/DaylightTests"
        )
    ]
)
