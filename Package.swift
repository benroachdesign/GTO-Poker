// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "GTOPoker",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "GTOPoker",
            targets: ["GTOPoker"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "GTOPoker",
            dependencies: [],
            path: "GTOPoker",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
