// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpaceMouseKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpaceMouseKit", targets: ["SpaceMouseKit"]),
        .library(name: "SpaceMouseBroker", targets: ["SpaceMouseBroker"]),
    ],
    targets: [
        // Model catalog and report decoding; pure, no IOKit (taken from Kugelblitz's copy, ADR-0001).
        .target(name: "SpaceMouseKit"),
        // The broker's rules and wire format: who gets a SpaceMouse, how clients and broker talk (ADR-0001).
        .target(name: "SpaceMouseBroker", dependencies: ["SpaceMouseKit"]),
        // Spike: broker and client in one command-line tool, to try election, handover and seizing (docs/spike.md).
        .executableTarget(name: "smk-spike", dependencies: ["SpaceMouseKit", "SpaceMouseBroker"]),
        .testTarget(name: "SpaceMouseKitTests", dependencies: ["SpaceMouseKit"]),
        .testTarget(name: "SpaceMouseBrokerTests", dependencies: ["SpaceMouseBroker"]),
    ]
)
