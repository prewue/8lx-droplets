// swift-tools-version: 6.2
import PackageDescription

// K*llTree's tests, outside its package: the Store takes no test target. Run
// `swift test` here. Everything they close is their own: a throwaway executable
// at a unique path, and a launchd job of their own.
let package = Package(
    name: "KillTreeTests",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../killtree"),
        .package(url: "https://gitlab.com/droppyformac1/droppykit.git", exact: "1.20.1")
    ],
    targets: [
        .testTarget(
            name: "KillTreeTests",
            dependencies: [
                .product(name: "KillTree", package: "killtree"),
                .product(name: "DroppyKitHarness", package: "droppykit")
            ]
        )
    ]
)
