// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GTOCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "AppUI",
            targets: ["AppUI"]),
    ],
    targets: [
        .target(
            name: "PokerDomain"
        ),
        .target(
            name: "ChartData",
            dependencies: ["PokerDomain"],
            resources: [
                .copy("Resources/poker_ranges.json")
            ]
        ),
        .target(
            name: "AppUI",
            dependencies: ["PokerDomain", "ChartData"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PokerDomainTests",
            dependencies: ["PokerDomain"]
        ),
        .testTarget(
            name: "ChartDataTests",
            dependencies: ["ChartData"]
        ),
        .testTarget(
            name: "AppUITests",
            dependencies: ["AppUI", "ChartData", "PokerDomain"]
        ),
    ]
)
