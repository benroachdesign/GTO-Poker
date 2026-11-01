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
        .executable(
            name: "chartc",
            targets: ["chartc"]),
    ],
    targets: [
        .target(
            name: "PokerDomain"
        ),
        .target(
            name: "ChartData",
            dependencies: ["PokerDomain"],
            resources: [
                .copy("Resources/6max-100.json")
            ]
        ),
        .target(
            name: "ChartCompiler",
            dependencies: ["ChartData", "PokerDomain"]
        ),
        .executableTarget(
            name: "chartc",
            dependencies: ["ChartCompiler", "ChartData"]
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
            dependencies: ["ChartData", "PokerDomain"]
        ),
        .testTarget(
            name: "ChartCompilerTests",
            dependencies: ["ChartCompiler", "ChartData", "PokerDomain"]
        ),
        .testTarget(
            name: "AppUITests",
            dependencies: ["AppUI", "ChartData", "PokerDomain"]
        ),
    ]
)
