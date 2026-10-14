import Foundation
import IOKit.hid
import SpaceMouseKit

/// Every attached SpaceMouse of a known model, seized while `wanted` (ADR-0001). A trimmed copy of Kugelblitz's
/// `HIDReader`: own device object by registry ID, seize, buffer alive until the cancel handler ran. Main queue only.
@MainActor
final class Devices {
    struct Entry {
        let id: String
        let model: SpaceMouseModel
        var state = "closed"
        var device: IOHIDDevice?
        var reports: Reports?
        var attempt = 0
    }

    var onAxes: (String, SpaceMouseAxes) -> Void = { _, _ in }
    var onButtons: (String, SpaceMouseButtons) -> Void = { _, _ in }
    var log: (String) -> Void = { _ in }

    private var manager: IOHIDManager?
    /// By registry ID of the manager's device object.
    private var entries: [UInt64: Entry] = [:]
    private var wanted = false

    var list: [BrokerDevice] { entries.values.sorted { $0.id < $1.id }.map { BrokerDevice(id: $0.id, model: $0.model.name, state: $0.state) } }

    struct BrokerDevice { let id: String, model: String, state: String }

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

    func want(_ wanted: Bool) {
        guard wanted != self.wanted else { return }
        self.wanted = wanted
        for key in entries.keys { wanted ? open(key) : close(key) }
    }

    func stop() {
        for key in entries.keys { close(key) }
        if let manager { IOHIDManagerCancel(manager) }
        manager = nil
    }

    private func appeared(_ managed: IOHIDDevice) {
        guard let key = Self.registryID(of: managed), entries[key] == nil,
              let vendor = IOHIDDeviceGetProperty(managed, kIOHIDVendorIDKey as CFString) as? Int,
              let product = IOHIDDeviceGetProperty(managed, kIOHIDProductIDKey as CFString) as? Int,
              let model = SpaceMouseModel.matching(vendorID: vendor, productID: product) else { return }
        // Identity: serial number where the device has one, else the USB port (ADR-0001, several SpaceMice).
        let serial = (IOHIDDeviceGetProperty(managed, kIOHIDSerialNumberKey as CFString) as? String).flatMap { $0.isEmpty ? nil : $0 }
        let location = IOHIDDeviceGetProperty(managed, kIOHIDLocationIDKey as CFString) as? Int ?? 0
        let id = serial.map { "serial:\($0)" } ?? String(format: "port:%04x:%04x@%08x", vendor, product, location)
        entries[key] = Entry(id: id, model: model)
        log("device appeared: \(model.name) \(id)")
        if wanted { open(key) }
    }

    private func vanished(_ managed: IOHIDDevice) {
        guard let key = Self.registryID(of: managed), let entry = entries[key] else { return }
        close(key)
        entries[key] = nil
        log("device gone: \(entry.model.name) \(entry.id)")
    }

    private func open(_ key: UInt64) {
        guard let entry = entries[key], entry.device == nil else { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(key))
        guard service != 0, let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else {
            if service != 0 { IOObjectRelease(service) }
            entries[key]?.state = "not reachable"
            return
        }
        IOObjectRelease(service)
        let size = max((IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int) ?? 64, 64)
        let id = entry.id
        let reports = Reports(size: size, model: entry.model,
                              onAxes: { [weak self] in self?.onAxes(id, $0) },
                              onButtons: { [weak self] in self?.onButtons(id, $0) })
        IOHIDDeviceRegisterInputReportCallback(device, reports.buffer, size, { context, result, _, _, _, report, length in
            guard result == kIOReturnSuccess, let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<Reports>.fromOpaque(context).takeUnretainedValue().ingest(UnsafeBufferPointer(start: report, count: length))
            }
        }, Unmanaged.passUnretained(reports).toOpaque())
        IOHIDDeviceSetDispatchQueue(device, .main)
        let started = Date()
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        let took = Int(Date().timeIntervalSince(started) * 1000)
        guard result == kIOReturnSuccess else {
            IOHIDDeviceSetCancelHandler(device) { withExtendedLifetime((device, reports)) {} }
            IOHIDDeviceCancel(device)
            let busy = result == kIOReturnExclusiveAccess
            entries[key]?.state = busy ? "busy (exclusive access)" : String(format: "open failed 0x%08X", UInt32(bitPattern: result))
            log("seize \(entry.id): \(entries[key]!.state) after \(took) ms")
            // Another process still holds it (a broker handing over closes first): retry for 2 s, like SeizeClaim.
            if busy, entries[key]!.attempt < 20 {
                entries[key]?.attempt += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self, self.wanted else { return }
                    self.open(key)
                }
            }
            return
        }
        IOHIDDeviceActivate(device)
        entries[key]?.device = device
        entries[key]?.reports = reports
        entries[key]?.state = "open"
        entries[key]?.attempt = 0
        log("seize \(entry.id): open after \(took) ms")
    }

    private func close(_ key: UInt64) {
        guard let device = entries[key]?.device, let reports = entries[key]?.reports else { return }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDDeviceSetCancelHandler(device) { withExtendedLifetime((device, reports)) {} }
        IOHIDDeviceCancel(device)
        entries[key]?.device = nil
        entries[key]?.reports = nil
        entries[key]?.state = "closed"
        log("released \(entries[key]!.id)")
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
    private var pending = SpaceMouseAxes.zero
    private var buttons: SpaceMouseButtons = []

    init(size: Int, model: SpaceMouseModel, onAxes: @escaping (SpaceMouseAxes) -> Void,
         onButtons: @escaping (SpaceMouseButtons) -> Void) {
        buffer = .allocate(capacity: size)
        self.model = model
        self.onAxes = onAxes
        self.onButtons = onButtons
    }

    deinit { buffer.deallocate() }

    func ingest(_ bytes: UnsafeBufferPointer<UInt8>) {
        if let now = SpaceMouseReport.buttons(bytes, model: model) {
            if now != buttons {
                buttons = now
                onButtons(now)
            }
        } else if SpaceMouseReport.take(bytes, into: &pending), SpaceMouseReport.completes(bytes) {
            onAxes(pending)
        }
    }
}
