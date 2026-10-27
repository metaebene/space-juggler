import AppKit
import SpaceJugglerCore
import SpaceJugglerProtocol

/// Wins the election or leaves, runs the broker and shows its menu bar item if a developer turned it on
/// (ADR-0001, ADR-0002, ADR-0011).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let place = BrokerPlace.standard
    private var broker: Broker?
    private var statusItem: NSStatusItem?
    private var menuBarSetting: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch Election.run(place: place, version: SpaceJuggler.version, log: { [place] in place.appendLog($0) }) {
        case .elected(let lockFile):
            let broker = Broker(record: .init(version: SpaceJuggler.version, path: Bundle.main.bundlePath))
            broker.onChange = { [weak self] in self?.updateIcon() }
            broker.onLeave = { NSApp.terminate(nil) }
            self.broker = broker
            followMenuBarSetting()
            broker.start(lockFile: lockFile)
            place.appendLog("permission to listen (Input Monitoring): \(Self.listenAccess) — \(Bundle.main.bundlePath)")
        case .stays(let running):
            place.appendLog("Space Juggler v\(running) runs and stays (this is v\(SpaceJuggler.version), \(Bundle.main.bundlePath))")
            NSApp.terminate(nil)
        case .failed(let reason):
            place.appendLog("not started: \(reason)")
            NSApp.terminate(nil)
        }
    }

    /// For ADR-0002's open question: whether this process may listen to HID input, without asking.
    private static var listenAccess: String {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: "granted"
        case kIOHIDAccessTypeDenied: "denied"
        default: "not determined"
        }
    }

    // MARK: - Menu bar item

    /// Only for developers (ADR-0011): `defaults write me.metaebene.SpaceJuggler showsMenuBarItem -bool YES`,
    /// followed while running, also when changed from outside.
    private func followMenuBarSetting() {
        menuBarSetting = UserDefaults.standard.observe(\.showsMenuBarItem, options: [.initial]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }
    }

    private func updateStatusItem() {
        let shows = UserDefaults.standard.showsMenuBarItem
        guard shows != (statusItem != nil) else { return }
        if shows {
            showStatusItem()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        place.appendLog("menu bar item \(shows ? "shown" : "hidden") (showsMenuBarItem)")
    }

    private func showStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.image()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        updateIcon()
    }

    /// Dimmed while nobody gets the input.
    private func updateIcon() {
        statusItem?.button?.appearsDisabled = !(broker?.status.clients.contains(where: \.holds) ?? false)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let broker else { return }
        let status = broker.status

        if status.devices.isEmpty {
            menu.addItem(disabled(String(localized: "No SpaceMouse connected")))
        } else {
            menu.addItem(.sectionHeader(title: String(localized: "SpaceMouse")))
            for device in status.devices {
                // The printed serial number tells two of one model apart (ADR-0003); models without one show none.
                var title = device.name
                if let serial = device.serialNumber { title += " \(serial)" }
                title += " (\(device.transport))"
                if let battery = device.battery { title += " – \(battery) %" }
                let item = NSMenuItem(title: title, action: #selector(toggleDevice(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = device.id
                item.state = device.enabled ? .on : .off
                // A model nobody here has checked at a device (ADR-0005) says so.
                item.toolTip = device.knowledge == nil || device.knowledge == .checked
                    ? device.id : device.id + "\n" + String(localized: "Not yet checked at a device")
                menu.addItem(item)
            }
        }

        if status.driver == true {
            menu.addItem(disabled(String(localized: "Through the 3Dconnexion driver")))
        }

        menu.addItem(.separator())
        if let holder = status.clients.first(where: \.holds) {
            menu.addItem(disabled(String(localized: "In use by \(holder.name)")))
        } else {
            menu.addItem(disabled(String(localized: "Not in use")))
        }
        for client in status.clients where !client.holds {
            menu.addItem(disabled(String(localized: "Waiting: \(client.name)")))
        }

        menu.addItem(.separator())
        let log = NSMenuItem(title: String(localized: "Show Log"), action: #selector(showLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)
        menu.addItem(disabled("\(SpaceJuggler.appName) \(SpaceJuggler.version)"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func toggleDevice(_ sender: NSMenuItem) {
        guard let broker, let id = sender.representedObject as? String else { return }
        broker.setEnabled(!broker.isEnabled(id), device: id)
    }

    @objc private func showLog() {
        NSWorkspace.shared.open(place.log)
    }
}

extension UserDefaults {
    /// Observable from outside the process, as `defaults write` changes it (ADR-0011).
    @objc dynamic fileprivate var showsMenuBarItem: Bool { bool(forKey: "showsMenuBarItem") }
}
