// swift-tools-version: 6.2
import PackageDescription

// Brightnesss's tests, outside its package: the Store takes no test target.
// Run `swift test` here. They run on the harness's dry run and never move the panel.
let package = Package(
    name: "BrightnesssTests",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../brightnesss"),
        .package(url: "https://gitlab.com/droppyformac1/droppykit.git", exact: "1.20.1")
    ],
    targets: [
        .testTarget(
            name: "BrightnesssTests",
            dependencies: [
                .product(name: "Brightnesss", package: "brightnesss"),
                .product(name: "DroppyKitHarness", package: "droppykit")
            ]
        )
    ]
)
