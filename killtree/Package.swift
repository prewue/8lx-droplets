// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Killtee",
    platforms: [.macOS(.v14)],
    products: [
        // A droplet is a loadable bundle, so its product is a dynamic library.
        // Do not make it static: the app already carries DroppyKit, and a
        // second copy inside the droplet gives the same type two metadata
        // records, which fails every cast between them.
        .library(name: "Killtee", type: .dynamic, targets: ["Killtee"])
    ],
    dependencies: [
        .package(url: "https://gitlab.com/droppyformac1/droppykit.git", from: "1.9.0")
    ],
    targets: [
        .target(
            name: "Killtee",
            dependencies: [.product(name: "DroppyKit", package: "droppykit")]
        ),
        .executableTarget(
            name: "KillteeHarness",
            dependencies: [
                "Killtee",
                .product(name: "DroppyKitHarness", package: "droppykit")
            ]
        )
    ]
)
