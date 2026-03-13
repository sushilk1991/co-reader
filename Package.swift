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
            path: "Sources/CoReaderApp",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("PDFKit")
            ]
        ),
        .testTarget(
            name: "CoReaderAppTests",
            dependencies: ["CoReaderApp"],
            path: "Tests/CoReaderAppTests"
        )
    ]
)
