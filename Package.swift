// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Coreader",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "CoreaderKit", targets: ["CoreaderKit"]),
        .executable(name: "coreader", targets: ["coreader-cli"]),
    ],
    targets: [
        // Platform-neutral core shared by the Mac app, the CLI and the future iOS app.
        // No AppKit/UIKit/SwiftUI here.
        .target(name: "CoreaderKit", path: "Sources/CoreaderKit"),
        .executableTarget(name: "coreader-cli", dependencies: ["CoreaderKit"], path: "Sources/coreader-cli"),
        .testTarget(name: "CoreaderKitTests", dependencies: ["CoreaderKit"], path: "Tests/CoreaderKitTests"),
    ]
)
