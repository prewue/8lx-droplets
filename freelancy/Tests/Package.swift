// swift-tools-version: 6.2
import PackageDescription

// The droplet's tests, a package of their own: the Store builds no tests and
// refuses a test target in a droplet's Package.swift, so they live beside it
// and reach the droplet by path. Run `swift test` from this folder.
let package = Package(
    name: "FreelanceTrackerTests",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .testTarget(
            name: "FreelanceTrackerTests",
            dependencies: [.product(name: "FreelanceTracker", package: "freelance-tracker")]
        )
    ]
)
