import AppKit
import Foundation
import SpaceMouseBroker

/// Spike for ADR-0001 (docs/spike.md):
///   smk-spike broker [--version N] [--linger S] [--no-devices]
///   smk-spike client --name NAME [--app BUNDLE-ID]... [--background] [--version N] [--seconds S] [--quiet]
///   smk-spike status
/// `SMK_HOME` moves lock, socket and log out of Application Support.

let executablePath = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]

let started = Date()

func say(_ text: String) {
    print(String(format: "%7.3f ", Date().timeIntervalSince(started)) + text)
    fflush(stdout)
}

struct Options {
    var values: [String: [String]] = [:]
    var flags: Set<String> = []

    init(_ arguments: ArraySlice<String>) {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            guard argument.hasPrefix("--") else { continue }
            let key = String(argument.dropFirst(2))
            if ["background", "no-devices", "quiet"].contains(key) {
                flags.insert(key)
            } else if let value = iterator.next() {
                values[key, default: []].append(value)
            }
        }
    }

    func int(_ key: String, _ fallback: Int) -> Int { values[key]?.last.flatMap(Int.init) ?? fallback }
}

let arguments = CommandLine.arguments
let command = arguments.count > 1 ? arguments[1] : "status"
let options = Options(arguments.dropFirst(2))
let place = BrokerPlace.standard

// The broker reads the frontmost app from NSWorkspace; an application object without UI keeps that current.
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)

MainActor.assumeIsolated {
    switch command {
    case "broker":
        let version = options.int("version", 1)
        guard let lock = Broker.acquireLock(place: place, version: version) else { exit(0) }
        let broker = Broker(version: version, place: place, linger: TimeInterval(options.int("linger", 10)),
                            usesDevices: !options.flags.contains("no-devices"), lockFD: lock)
        broker.start()
        objc_setAssociatedObject(NSApp!, "broker", broker, .OBJC_ASSOCIATION_RETAIN)
    case "client":
        let name = options.values["name"]?.last ?? "client-\(getpid())"
        let claim = Claim(apps: options.values["app"] ?? [], background: options.flags.contains("background"))
        let client = Client(name: name, claim: claim, version: options.int("version", 1), place: place,
                            quiet: options.flags.contains("quiet"))
        client.start()
        objc_setAssociatedObject(NSApp!, "client", client, .OBJC_ASSOCIATION_RETAIN)
        if let seconds = options.values["seconds"]?.last.flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                say("[\(name)] done")
                exit(0)
            }
        }
    case "status":
        guard let fd = UnixSocket.connect(to: place.socket.path) else {
            print("no broker")
            exit(1)
        }
        let connection = LineConnection<ClientMessage, BrokerMessage>(fd: fd)
        connection.onMessage = { message in
            guard case .status(let status) = message else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try! encoder.encode(status), as: UTF8.self))
            exit(0)
        }
        connection.start()
        connection.send(.hello(protocolVersion: Wire.protocolVersion, processID: getpid(), name: "status", claim: nil))
        connection.send(.status)
        objc_setAssociatedObject(NSApp!, "status", connection, .OBJC_ASSOCIATION_RETAIN)
    default:
        print("usage: smk-spike broker|client|status …")
        exit(2)
    }
}

RunLoop.main.run()
