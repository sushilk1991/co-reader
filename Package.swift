// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CoReader",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "CoReaderApp",
            targets: ["CoReaderApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CoReaderApp",
            path: "Sources/CoReaderApp"
        ),
        .testTarget(
            name: "CoReaderAppTests",
            dependencies: ["CoReaderApp"],
            path: "Tests/CoReaderAppTests"
        )
    ]
)
