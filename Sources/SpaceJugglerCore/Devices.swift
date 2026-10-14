import Foundation
import IOKit.hid
import SpaceJugglerProtocol

/// Every attached SpaceMouse of a known model (ADR-0001, ADR-0003). Opened seized only while `wanted`; own device
/// object by registry ID (never configure the manager's), report buffer alive until the cancel handler ran, the only
/// writes are output report 4 (LED) and the only feature report read is the serial number (GET). Main queue only.
@MainActor
final class Devices {
    private struct Entry {
        var info: SpaceMouseDevice
        let model: SpaceMouseModel
        var device: IOHIDDevice?
        var reports: Reports?
        var attempt = 0
    }

    var onAxes: (String, SpaceMouseAxes) -> Void = { _, _ in }
    var onButtons: (String, SpaceMouseButtons) -> Void = { _, _ in }
    /// The device list changed (appeared, gone, opened, battery, LED).
    var onChange: () -> Void = {}
    var log: (String) -> Void = { _ in }
    var isEnabled: (String) -> Bool = { _ in true }

    private var manager: IOHIDManager?
    /// By registry ID of the manager's device object.
    private var entries: [UInt64: Entry] = [:]
    private var wanted = false

    var list: [SpaceMouseDevice] {
        entries.values.map { entry in
            var info = entry.info
            info.enabled = isEnabled(info.id)
            return info
        }.sorted { $0.id < $1.id }
    }

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = SpaceMouseModel.known.map {
            [kIOHIDVendorIDKey: $0.vendorID, kIOHIDProductIDKey: $0.productID,
             kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop, kIOHIDPrimaryUsageKey: kHIDUsage_GD_MultiAxisController]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            MainActor.assumeIsolated { Unmanaged<Devices>.fromOpaque(context!).takeUnretainedValue().appeared(device) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            MainActor.assumeIsolated { Unmanaged<Devices>.fromOpaque(context!).takeUnretainedValue().vanished(device) }
        }, context)
        IOHIDManagerSetDispatchQueue(manager, .main)
        IOHIDManagerActivate(manager)
        self.manager = manager
    }

    /// Seize every device (true) or let them all go (false).
    func want(_ wanted: Bool) {
        guard wanted != self.wanted else { return }
        self.wanted = wanted
        for key in entries.keys { wanted ? open(key) : close(key) }
    }

    func stop() {
        wanted = false
        for key in entries.keys { close(key) }
        if let manager { IOHIDManagerCancel(manager) }
        manager = nil
    }

    /// Output report 4. A device not open is opened for the write and closed again; the Wireless lights only on its
    /// cable (`statusLEDNeedsCable`). Returns why not, or nil.
    func setLED(_ on: Bool, device id: String) -> String? {
        guard let key = entries.first(where: { $0.value.info.id == id })?.key, let entry = entries[key] else {
            return "no such device"
        }
        if entry.model.statusLEDNeedsCable, entry.info.isBluetooth { return "the LED lights only on the USB cable" }
        var temporary: IOHIDDevice?
        let device: IOHIDDevice
        if let open = entry.device {
            device = open
        } else {
            guard let created = Self.ownDevice(key), IOHIDDeviceOpen(created, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess else {
                return "device busy"
            }
            temporary = created
            device = created
        }
        defer { if let temporary { IOHIDDeviceClose(temporary, IOOptionBits(kIOHIDOptionsTypeNone)) } }
        var report: [UInt8] = [4, on ? 1 : 0]
        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 4, &report, report.count)
        guard result == kIOReturnSuccess else { return String(format: "LED not switched (0x%08X)", UInt32(bitPattern: result)) }
        entries[key]?.info.led = on
        onChange()
        return nil
    }

    /// What IOKit says about a device when it appears.
    private struct Found: Sendable {
        let vendor: Int, product: Int
        let transport: String
        let usbSerial: String?
        let address: String?
        let location: Int
    }

    private func appeared(_ managed: IOHIDDevice) {
        guard let key = Self.registryID(of: managed), entries[key] == nil,
              let vendor = IOHIDDeviceGetProperty(managed, kIOHIDVendorIDKey as CFString) as? Int,
              let product = IOHIDDeviceGetProperty(managed, kIOHIDProductIDKey as CFString) as? Int,
              let model = SpaceMouseModel.matching(vendorID: vendor, productID: product) else { return }
        let found = Found(
            vendor: vendor, product: product,
            transport: IOHIDDeviceGetProperty(managed, kIOHIDTransportKey as CFString) as? String ?? "USB",
            usbSerial: (IOHIDDeviceGetProperty(managed, kIOHIDSerialNumberKey as CFString) as? String).flatMap { $0.isEmpty ? nil : $0 },
            address: IOHIDDeviceGetProperty(managed, "DeviceAddress" as CFString) as? String,
            location: IOHIDDeviceGetProperty(managed, kIOHIDLocationIDKey as CFString) as? Int ?? 0)
        guard found.usbSerial == nil, let reportID = model.serialFeatureReportID else {
            return register(key, model: model, found: found, serial: found.usbSerial)
        }
        // The printed serial number (ADR-0003): a GET takes a round trip over Bluetooth, so off the main queue.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let serial = Self.readSerialNumber(key, reportID: reportID)
            Task { @MainActor in self?.register(key, model: model, found: found, serial: serial) }
        }
    }

    private func register(_ key: UInt64, model: SpaceMouseModel, found: Found, serial: String?) {
        guard entries[key] == nil else { return }
        let id = Self.identity(serial: serial, transport: found.transport, address: found.address, vendor: found.vendor,
                               product: found.product, location: found.location)
        entries[key] = Entry(info: SpaceMouseDevice(id: id, vendorID: found.vendor, productID: found.product, name: model.name,
                                                    transport: found.transport, serialNumber: serial),
                             model: model)
        log("device appeared: \(model.name) \(id) (\(found.transport))")
        if wanted { open(key) }
        onChange()
    }

    /// Serial number, else Bluetooth address, else model + USB port (ADR-0003).
    nonisolated static func identity(serial: String?, transport: String, address: String?, vendor: Int, product: Int,
                                     location: Int) -> String {
        if let serial { return "serial:\(serial)" }
        if transport.caseInsensitiveCompare("Bluetooth") == .orderedSame, let address, !address.isEmpty {
            return "bt:\(address.lowercased().replacingOccurrences(of: "-", with: ":"))"
        }
        return String(format: "port:%04x:%04x@%08x", vendor, product, location)
    }

    private nonisolated static func readSerialNumber(_ key: UInt64, reportID: UInt8) -> String? {
        guard let device = ownDevice(key),
              IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return nil }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        var buffer = [UInt8](repeating: 0, count: 8)
        buffer[0] = reportID
        var length = CFIndex(buffer.count)
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), &buffer, &length) == kIOReturnSuccess else {
            return nil
        }
        return SpaceMouseReport.serialNumber(Array(buffer.prefix(Int(length))))
    }

    private func vanished(_ managed: IOHIDDevice) {
        guard let key = Self.registryID(of: managed), let entry = entries[key] else { return }
        close(key)
        entries[key] = nil
        log("device gone: \(entry.info.name) \(entry.info.id)")
        onChange()
    }

    private func open(_ key: UInt64) {
        guard let entry = entries[key], entry.device == nil else { return }
        guard let device = Self.ownDevice(key) else {
            entries[key]?.info.state = "not reachable"
            return
        }
        let size = max((IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int) ?? 64, 64)
        let id = entry.info.id
        let reports = Reports(size: size, model: entry.model,
                              // Input of a device that is off reaches nobody (ADR-0003).
                              onAxes: { [weak self] axes in
                                  guard let self, self.isEnabled(id) else { return }
                                  self.onAxes(id, axes)
                              },
                              onButtons: { [weak self] held in
                                  guard let self, self.isEnabled(id) else { return }
                                  self.onButtons(id, held)
                              },
                              onBattery: { [weak self] percent, charging in self?.battery(key, percent, charging) })
        IOHIDDeviceRegisterInputReportCallback(device, reports.buffer, size, { context, result, _, _, _, report, length in
            guard result == kIOReturnSuccess, let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<Reports>.fromOpaque(context).takeUnretainedValue().ingest(UnsafeBufferPointer(start: report, count: length))
            }
        }, Unmanaged.passUnretained(reports).toOpaque())
        IOHIDDeviceSetDispatchQueue(device, .main)
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            IOHIDDeviceSetCancelHandler(device) { withExtendedLifetime((device, reports)) {} }
            IOHIDDeviceCancel(device)
            let busy = result == kIOReturnExclusiveAccess
            entries[key]?.info.state = busy ? "busy" : String(format: "open failed (0x%08X)", UInt32(bitPattern: result))
            if entries[key]!.attempt == 0 { log("seize \(id): \(entries[key]!.info.state)") }
            // Another process still holds it (a broker handing over closes first): retry for 2 s.
            if busy, entries[key]!.attempt < 20 {
                entries[key]?.attempt += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.wanted else { return }
                        self.open(key)
                    }
                }
            } else {
                onChange()
            }
            return
        }
        IOHIDDeviceActivate(device)
        entries[key]?.device = device
        entries[key]?.reports = reports
        entries[key]?.info.state = "open"
        entries[key]?.attempt = 0
        log("seized \(id)")
        onChange()
    }

    private func battery(_ key: UInt64, _ percent: Int, _ charging: Bool) {
        guard entries[key]?.info.battery != percent || entries[key]?.info.charging != charging else { return }
        entries[key]?.info.battery = percent
        entries[key]?.info.charging = charging
        onChange()
    }

    private func close(_ key: UInt64) {
        guard let device = entries[key]?.device, let reports = entries[key]?.reports else { return }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDDeviceSetCancelHandler(device) { withExtendedLifetime((device, reports)) {} }
        IOHIDDeviceCancel(device)
        entries[key]?.device = nil
        entries[key]?.reports = nil
        entries[key]?.info.state = "closed"
        log("released \(entries[key]!.info.id)")
        onChange()
    }

    private nonisolated static func ownDevice(_ key: UInt64) -> IOHIDDevice? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(key))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IOHIDDeviceCreate(kCFAllocatorDefault, service)
    }

    private static func registryID(of device: IOHIDDevice) -> UInt64? {
        var id: UInt64 = 0
        return IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id) == KERN_SUCCESS ? id : nil
    }
}

/// Report buffer of one open device; decodes on the main queue.
@MainActor
final class Reports {
    nonisolated(unsafe) let buffer: UnsafeMutablePointer<UInt8>
    private let model: SpaceMouseModel
    private let onAxes: (SpaceMouseAxes) -> Void
    private let onButtons: (SpaceMouseButtons) -> Void
    private let onBattery: (Int, Bool) -> Void
    private var pending = SpaceMouseAxes.zero
    private var buttons: SpaceMouseButtons = []

    init(size: Int, model: SpaceMouseModel, onAxes: @escaping (SpaceMouseAxes) -> Void,
         onButtons: @escaping (SpaceMouseButtons) -> Void, onBattery: @escaping (Int, Bool) -> Void) {
        buffer = .allocate(capacity: size)
        self.model = model
        self.onAxes = onAxes
        self.onButtons = onButtons
        self.onBattery = onBattery
    }

    deinit { buffer.deallocate() }

    func ingest(_ bytes: UnsafeBufferPointer<UInt8>) {
        if let now = SpaceMouseReport.buttons(bytes, model: model) {
            if now != buttons {
                buttons = now
                onButtons(now)
            }
        } else if let battery = SpaceMouseReport.battery(bytes) {
            onBattery(battery.percent, battery.charging)
        } else if SpaceMouseReport.take(bytes, into: &pending), SpaceMouseReport.completes(bytes) {
            onAxes(pending)
        }
    }
}
