// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SnapMark",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure model/rendering code: no UI, fully unit-testable.
        .target(name: "SnapMarkCore"),
        .executableTarget(
            name: "SnapMark",
            dependencies: ["SnapMarkCore"]
        ),
        // The CLT-only toolchain ships Testing without its Foundation cross-import overlay.
        .testTarget(
            name: "SnapMarkCoreTests",
            dependencies: ["SnapMarkCore"],
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-disable-cross-import-overlays"])]
        ),
    ]
)
