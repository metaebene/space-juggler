// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpaceMouseKit",
    platforms: [.macOS(.v14)],
    products: [
        // Model catalog and report decoding, usable on their own (ADR-0001).
        .library(name: "SpaceMouseKit", targets: ["SpaceMouseKit"]),
        // What a program links to get the SpaceMouse through Space Juggler (ADR-0001, ADR-0002).
        .library(name: "SpaceJugglerClient", targets: ["SpaceJugglerClient"]),
        // The broker; wrapped into Space Juggler.app by Scripts/build-space-juggler.sh (ADR-0002).
        .executable(name: "SpaceJuggler", targets: ["SpaceJuggler"]),
        .executable(name: "space-juggler-cli", targets: ["space-juggler-cli"]),
    ],
    targets: [
        // Models, reports, the 3DxWare client API's device state; pure, no IOKit.
        .target(name: "SpaceMouseKit"),
        // What broker and clients share: messages, places, sockets (ADR-0001).
        .target(name: "SpaceJugglerProtocol", dependencies: ["SpaceMouseKit"]),
        // The broker itself: election, devices, arbitration, server. Used by the app and the CLI.
        .target(name: "SpaceJugglerCore", dependencies: ["SpaceMouseKit", "SpaceJugglerProtocol"]),
        // The client side for apps: connect, start the newest broker, reconnect, claim, events.
        .target(name: "SpaceJugglerClient", dependencies: ["SpaceMouseKit", "SpaceJugglerProtocol"]),
        // Space Juggler.app: the broker with its menu bar item.
        .executableTarget(name: "SpaceJuggler", dependencies: ["SpaceJugglerCore"]),
        // Status, test clients and a broker without UI, for tests and diagnosis (docs/spike.md).
        .executableTarget(name: "space-juggler-cli", dependencies: ["SpaceJugglerCore", "SpaceJugglerClient"]),
        .testTarget(name: "SpaceMouseKitTests", dependencies: ["SpaceMouseKit"]),
        .testTarget(name: "SpaceJugglerTests", dependencies: ["SpaceJugglerCore", "SpaceJugglerClient"]),
    ]
)
