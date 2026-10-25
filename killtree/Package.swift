// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KillTree",
    platforms: [.macOS(.v14)],
    products: [
        // A droplet is a loadable bundle, so its product is a dynamic library.
        // Do not make it static: the app already carries DroppyKit, and a
        // second copy inside the droplet gives the same type two metadata
        // records, which fails every cast between them.
        .library(name: "KillTree", type: .dynamic, targets: ["KillTree"])
    ],
    dependencies: [
        .package(url: "https://gitlab.com/droppyformac1/droppykit.git", from: "1.9.0")
    ],
    targets: [
        .target(
            name: "KillTree",
            dependencies: [.product(name: "DroppyKit", package: "droppykit")]
        ),
        .executableTarget(
            name: "KillTreeHarness",
            dependencies: [
                "KillTree",
                .product(name: "DroppyKitHarness", package: "droppykit")
            ]
        )
    ]
)
