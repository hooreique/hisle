// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "hisle-core",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "HisleCore",
            targets: ["HisleCore"]
        ),
        // The pinned nixpkgs SwiftPM cannot run XCTest/Testing here; keep the
        // core contract check as an executable and run it through Make.
        .executable(
            name: "hisle-core-spec-check",
            targets: ["HisleCoreSpecCheck"]
        ),
    ],
    targets: [
        .target(
            name: "HisleCore",
            resources: [
                .process("Resources/cole-sebeol-spec.txt"),
            ]
        ),
        .executableTarget(
            name: "HisleCoreSpecCheck",
            dependencies: ["HisleCore"]
        ),
    ]
)
