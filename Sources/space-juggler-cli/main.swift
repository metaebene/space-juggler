import AppKit
import Foundation
import SpaceJugglerClient
import SpaceJugglerCore

/// Diagnosis and tests for Space Juggler (docs/spike.md):
///   space-juggler-cli status
///   space-juggler-cli client --name NAME [--app BUNDLE-ID]... [--background] [--version N] [--seconds S] [--quiet]
///                            [--launch-app PATH] [--raw]  (default: start `space-juggler-cli broker` when nobody
///                                                         answers; --raw prints every input report, ADR-0006)
///   space-juggler-cli broker [--version N] [--linger S] [--no-devices]
///   space-juggler-cli led DEVICE-ID on|off
///   space-juggler-cli describe DEVICE-ID         (registry, report descriptor, feature reports; ADR-0006)
/// `SPACE_JUGGLER_HOME` moves lock, socket and log out of `~/Library/Application Support/Space Juggler`.

let executablePath = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
let started = Date()

func say(_ text: String) {
    print(String(format: "%7.3f ", Date().timeIntervalSince(started)) + text)
    fflush(stdout)
}

func printJSON(_ value: some Encodable) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try! encoder.encode(value), as: UTF8.self))
}

struct Options {
    var values: [String: [String]] = [:]
    var flags: Set<String> = []
    var positional: [String] = []

    init(_ arguments: ArraySlice<String>) {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            guard argument.hasPrefix("--") else {
                positional.append(argument)
                continue
            }
            let key = String(argument.dropFirst(2))
            if ["background", "no-devices", "quiet", "raw"].contains(key) {
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

nonisolated(unsafe) var keptAlive: [AnyObject] = []

/// Sends one request and hands the answers to `handle` until it returns true.
@MainActor func ask(_ message: ClientMessage, then handle: @escaping (BrokerMessage) -> Bool) {
    guard let fd = UnixSocket.connect(to: place.socket.path) else {
        print("no Space Juggler running")
        exit(1)
    }
    let connection = LineConnection<ClientMessage, BrokerMessage>(fd: fd)
    connection.onMessage = { if handle($0) { exit(0) } }
    connection.onClose = { exit(1) }
    connection.start()
    connection.send(.hello(Hello(version: SpaceJuggler.version, processID: getpid(), name: "space-juggler-cli", claim: nil)))
    connection.send(message)
    keptAlive.append(connection)
}

MainActor.assumeIsolated {
    switch command {
    case "broker":
        let version = options.int("version", SpaceJuggler.version)
        switch Election.run(place: place, version: version, log: { say($0) }) {
        case .elected(let lockFile):
            let broker = Broker(version: version, place: place, linger: TimeInterval(options.int("linger", 10)),
                                usesDevices: !options.flags.contains("no-devices"),
                                record: .init(version: version, path: executablePath, arguments: ["broker", "--version", String(version)]))
            broker.log = { say($0) }
            broker.start(lockFile: lockFile)
            keptAlive.append(broker)
        case .stays(let running):
            say("Space Juggler v\(running) runs and stays (this is v\(version))")
            exit(0)
        case .failed(let reason):
            say(reason)
            exit(1)
        }

    case "client":
        let name = options.values["name"]?.last ?? "client-\(getpid())"
        let version = options.int("version", SpaceJuggler.version)
        let claim = Claim(apps: options.values["app"] ?? [], background: options.flags.contains("background"),
                          raw: options.flags.contains("raw") ? true : nil)
        let launcher: SpaceJugglerConnection.Launcher = options.values["launch-app"]?.last.map { .app(URL(fileURLWithPath: $0)) }
            ?? .executable(path: executablePath, arguments: ["broker", "--version", String(version)])
        let client = SpaceJugglerConnection(name: name, claim: claim, launcher: launcher, place: place, version: version)
        var axesCount = 0
        let quiet = options.flags.contains("quiet")
        client.onEvent = { event in
            switch event {
            case .connected(let brokerVersion): say("[\(name)] connected to Space Juggler v\(brokerVersion)")
            case .disconnected: say("[\(name)] Space Juggler gone")
            case .holding(let holds): say("[\(name)] \(holds ? "HOLDS the SpaceMouse" : "lost the SpaceMouse")")
            case .devices(let devices):
                if !quiet { say("[\(name)] devices: " + devices.map { "\($0.name) \($0.id) \($0.state)" }.joined(separator: "; ")) }
            case .axes(let axes, let device):
                axesCount += 1
                if !quiet, axesCount % 10 == 1 { say("[\(name)] \(device) \(axes)") }
            case .buttons(let held, let device): say("[\(name)] \(device) buttons \(held.rawValue) (all: \(client.heldButtons.rawValue))")
            case .unavailable(let reason): say("[\(name)] \(reason)")
            }
        }
        client.onReport = { bytes, device in
            say("[\(name)] \(device) report " + bytes.hex())
        }
        client.start()
        keptAlive.append(client)
        if let seconds = options.values["seconds"]?.last.flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                say("[\(name)] done")
                exit(0)
            }
        }

    case "status":
        ask(.status) { message in
            guard case .status(let status) = message else { return false }
            printJSON(status)
            return true
        }

    case "led":
        guard options.positional.count == 2 else {
            print("usage: space-juggler-cli led DEVICE-ID on|off")
            exit(2)
        }
        let on = options.positional[1] == "on"
        ask(.setLED(device: options.positional[0], on: on)) { message in
            guard case .devices(let devices) = message,
                  let device = devices.first(where: { $0.id == options.positional[0] }) else { return false }
            print("\(device.name): LED \(device.led.map { $0 ? "on" : "off" } ?? "unknown")")
            return device.led == on
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            print("no change reported (see broker.log)")
            exit(1)
        }

    case "describe":
        guard options.positional.count == 1 else {
            print("usage: space-juggler-cli describe DEVICE-ID")
            exit(2)
        }
        ask(.describe(device: options.positional[0])) { message in
            guard case .description(let description) = message else { return false }
            printJSON(description)
            if let parsed = HIDReportDescriptor(description.reportDescriptor) {
                for report in parsed.reports {
                    print(String(format: "%@ report 0x%02X: %d bytes", report.kind.rawValue, report.id, report.length))
                }
                print("axes ±\(parsed.axisLogicalMaximum ?? 0)\(parsed.axesDeclaredRelative ? " (declared relative)" : ""), "
                      + "buttons \(parsed.buttonUsages), LED \(parsed.hasLED)")
            }
            return true
        }

    default:
        print("usage: space-juggler-cli status | client … | broker … | led DEVICE on|off | describe DEVICE")
        exit(2)
    }
}

RunLoop.main.run()
