import Foundation
import IOKit.hid
import IOUSBHost
import SpaceJugglerProtocol

/// Every attached SpaceMouse: a Multi-axis Controller of Logitech or 3Dconnexion, of a model in the catalog or not
/// (ADR-0001, ADR-0003, ADR-0005). Opened seized only while `wanted`; own device object by registry ID (never configure
/// the manager's), report buffer alive until the cancel handler ran, the only writes are output report 4 (LED); feature
/// reports are only read (GET, through the HID device or, on USB, the control pipe): the serial number, and every one
/// for a description (ADR-0006). Main queue only.
@MainActor
final class Devices {
    private struct Entry {
        var info: SpaceMouseDevice
        let model: SpaceMouseModel
        /// The USB interface the HID device sits on (the Universal Receiver has one per slot).
        let interface: Int?
        var device: IOHIDDevice?
        var reports: Reports?
        var attempt = 0
    }

    var onAxes: (String, SpaceMouseAxes) -> Void = { _, _ in }
    var onButtons: (String, SpaceMouseButtons) -> Void = { _, _ in }
    /// Every input report as it came, while `wantsReports` says somebody takes them (ADR-0006).
    var onReport: (String, [UInt8]) -> Void = { _, _ in }
    var wantsReports: () -> Bool = { false }
    /// The device list changed (appeared, gone, opened, battery, LED).
    var onChange: () -> Void = {}
    var log: (String) -> Void = { _ in }
    var isEnabled: (String) -> Bool = { _ in true }

    private var manager: IOHIDManager?
    /// By registry ID of the manager's device object.
    private var entries: [UInt64: Entry] = [:]
    private var wanted = false
    /// 3Dconnexion's helper holds the devices; they are reported as "driver" (ADR-0004).
    var driverHolds = false

    var list: [SpaceMouseDevice] {
        entries.values.map { entry in
            var info = entry.info
            info.enabled = isEnabled(info.id)
            if driverHolds, info.state != "open" { info.state = "driver" }
            return info
        }.sorted { $0.id < $1.id }
    }

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // By usage pair, not primary usage: the Universal Receiver's slots are a vendor usage first (ADR-0005).
        let matching: [[String: Any]] = SpaceMouseModel.vendorIDs.map {
            [kIOHIDVendorIDKey: $0,
             kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_MultiAxisController]
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
        let interface: Int?
    }

    private func appeared(_ managed: IOHIDDevice) {
        guard let key = Self.registryID(of: managed), entries[key] == nil,
              let vendor = IOHIDDeviceGetProperty(managed, kIOHIDVendorIDKey as CFString) as? Int,
              let product = IOHIDDeviceGetProperty(managed, kIOHIDProductIDKey as CFString) as? Int else { return }
        let transport = IOHIDDeviceGetProperty(managed, kIOHIDTransportKey as CFString) as? String ?? "USB"
        // 3Dconnexion's driver publishes virtual devices of its own (docs/3dxware-package.md): never a SpaceMouse.
        guard !transport.localizedCaseInsensitiveContains("virtual") else { return }
        let descriptor = (IOHIDDeviceGetProperty(managed, kIOHIDReportDescriptorKey as CFString) as? Data)
            .flatMap { HIDReportDescriptor([UInt8]($0)) }
        guard let model = SpaceMouseModel.recognise(
            vendorID: vendor, productID: product,
            product: IOHIDDeviceGetProperty(managed, kIOHIDProductKey as CFString) as? String,
            descriptor: descriptor) else { return }
        let found = Found(
            vendor: vendor, product: product, transport: transport,
            usbSerial: (IOHIDDeviceGetProperty(managed, kIOHIDSerialNumberKey as CFString) as? String).flatMap { $0.isEmpty ? nil : $0 },
            address: IOHIDDeviceGetProperty(managed, "DeviceAddress" as CFString) as? String,
            location: IOHIDDeviceGetProperty(managed, kIOHIDLocationIDKey as CFString) as? Int ?? 0,
            interface: Self.interfaceNumber(of: IOHIDDeviceGetService(managed)))
        guard found.usbSerial == nil, let reportID = model.serialFeatureReportID else {
            return register(key, model: model, found: found, serial: found.usbSerial)
        }
        // The serial number (ADR-0003): a GET takes a round trip over Bluetooth, so off the main queue.
        let usb = found.transport.caseInsensitiveCompare("USB") == .orderedSame
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let bytes = Self.getFeature(key, reportID: reportID, length: 8)
                ?? (usb ? Self.getFeatureOverControlPipe(location: found.location, interface: found.interface ?? 0,
                                                         reportID: reportID, length: 8) : nil)
            let serial = bytes.flatMap(SpaceMouseReport.serialNumber)
            Task { @MainActor in self?.register(key, model: model, found: found, serial: serial) }
        }
    }

    private func register(_ key: UInt64, model: SpaceMouseModel, found: Found, serial: String?) {
        guard entries[key] == nil else { return }
        let id = Self.identity(serial: serial, transport: found.transport, address: found.address, vendor: found.vendor,
                               product: found.product, location: found.location,
                               slot: found.product == SpaceMouseModel.universalReceiverProductID ? found.interface : nil)
        entries[key] = Entry(info: SpaceMouseDevice(id: id, vendorID: found.vendor, productID: found.product, name: model.name,
                                                    transport: found.transport, serialNumber: serial,
                                                    bluetoothAddress: found.address.flatMap { $0.isEmpty ? nil : $0 },
                                                    locationID: found.location, knowledge: model.knowledge,
                                                    buttons: model.buttons, axisFullScale: model.axisFullScale,
                                                    hasLED: model.hasStatusLED),
                             model: model, interface: found.interface)
        log("device appeared: \(model) \(id) (\(found.transport))")
        if wanted { open(key) }
        onChange()
    }

    /// Serial number, else Bluetooth address, else model + USB port (ADR-0003), and the slot on a Universal Receiver
    /// (ADR-0005).
    nonisolated static func identity(serial: String?, transport: String, address: String?, vendor: Int, product: Int,
                                     location: Int, slot: Int? = nil) -> String {
        if let serial { return "serial:\(serial)" }
        if transport.caseInsensitiveCompare("Bluetooth") == .orderedSame, let address, !address.isEmpty {
            return "bt:\(address.lowercased().replacingOccurrences(of: "-", with: ":"))"
        }
        return String(format: "port:%04x:%04x@%08x", vendor, product, location) + (slot.map { "/\($0)" } ?? "")
    }

    /// The model a listed device was recognised as.
    func model(of id: String) -> SpaceMouseModel? {
        entries.values.first { $0.info.id == id }?.model
    }

    /// The `bInterfaceNumber` of the USB interface a HID device sits on; nil over Bluetooth.
    private nonisolated static func interfaceNumber(of service: io_service_t) -> Int? {
        IORegistryEntrySearchCFProperty(service, kIOServicePlane, "bInterfaceNumber" as CFString, kCFAllocatorDefault,
                                        IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? Int
    }

    /// A feature report through a HID device object of our own (opened without seizing, closed again), or through
    /// `device` when it is open already; report ID first. Nil when the GET fails.
    private nonisolated static func getFeature(_ key: UInt64, reportID: UInt8, length: Int, device open: IOHIDDevice? = nil) -> [UInt8]? {
        let device: IOHIDDevice
        if let open {
            device = open
        } else {
            guard let own = ownDevice(key), IOHIDDeviceOpen(own, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
                return nil
            }
            device = own
        }
        defer { if open == nil { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) } }
        var buffer = [UInt8](repeating: 0, count: max(length, 2))
        buffer[0] = reportID
        var count = CFIndex(buffer.count)
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), &buffer, &count) == kIOReturnSuccess else {
            return nil
        }
        return Array(buffer.prefix(Int(count)))
    }

    /// The same GET as a USB class request on the default pipe, for a device someone else holds (3Dconnexion's helper
    /// seizes every SpaceMouse, so opening its HID device fails): nothing is opened or written.
    private nonisolated static func getFeatureOverControlPipe(location: Int, interface: Int, reportID: UInt8,
                                                              length: Int) -> [UInt8]? {
        let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        matching[kIOPropertyMatchKey] = ["locationID": location]
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let usb = try? IOUSBHostDevice(__ioService: service, options: [], queue: nil, interestHandler: nil) else {
            return nil
        }
        defer { usb.destroy() }
        var request = IOUSBDeviceRequest()
        request.bmRequestType = 0xA1                        // class request to an interface, device to host
        request.bRequest = 0x01                             // GET_REPORT
        request.wValue = 0x0300 | UInt16(reportID)          // feature report
        request.wIndex = UInt16(interface)
        request.wLength = UInt16(max(length, 2))
        let data = NSMutableData(length: max(length, 2))!
        var count = 0
        guard (try? usb.__send(request, data: data, bytesTransferred: &count, completionTimeout: 1)) != nil else { return nil }
        return [UInt8](Data(referencing: data).prefix(count))
    }

    /// Everything that can be read about a device without changing it (ADR-0006), off the main queue.
    func describe(_ id: String, completion: @escaping @MainActor (DeviceDescription) -> Void) {
        guard let (key, entry) = entries.first(where: { $0.value.info.id == id }) else {
            return completion(DeviceDescription(device: id, error: "no such device"))
        }
        guard let service = Optional(IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(key))),
              service != 0 else {
            return completion(DeviceDescription(device: id, error: "not in the IORegistry"))
        }
        let properties = Self.properties(of: service)
        let bytes = (IORegistryEntryCreateCFProperty(service, kIOHIDReportDescriptorKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data).map { [UInt8]($0) } ?? []
        IOObjectRelease(service)
        let features = HIDReportDescriptor(bytes)?.reports.filter { $0.kind == .feature } ?? []
        let open = entry.device.map { UncheckedSendable($0) }
        let usb = entry.info.transport.caseInsensitiveCompare("USB") == .orderedSame
        let location = entry.info.locationID ?? 0, interface = entry.interface ?? 0
        DispatchQueue.global(qos: .userInitiated).async {
            var via: String?
            let reports = features.map { report -> DeviceDescription.FeatureReport in
                if let read = Self.getFeature(key, reportID: report.id, length: report.length, device: open?.value) {
                    via = via ?? "HID device"
                    return .init(id: Int(report.id), bytes: read)
                }
                if usb, let read = Self.getFeatureOverControlPipe(location: location, interface: interface,
                                                                   reportID: report.id, length: report.length) {
                    via = via ?? "control pipe"
                    return .init(id: Int(report.id), bytes: read)
                }
                return .init(id: Int(report.id), error: "GET failed")
            }
            let description = DeviceDescription(device: id, properties: properties, reportDescriptor: bytes,
                                                featureReports: reports, featureReportsVia: via)
            Task { @MainActor in completion(description) }
        }
    }

    /// The properties of a HID service that say what the device is, and those of the USB interface and device above
    /// it, as text. No serial numbers beyond what the device publishes itself.
    private nonisolated static func properties(of service: io_service_t) -> [String: String] {
        let own = ["VendorID", "ProductID", "Product", "Manufacturer", "VersionNumber", "Transport", "SerialNumber",
                   "LocationID", "PrimaryUsagePage", "PrimaryUsage", "DeviceUsagePairs", "MaxInputReportSize",
                   "MaxOutputReportSize", "MaxFeatureReportSize", "CountryCode", "ReportInterval", "DeviceAddress"]
        let above = ["bInterfaceNumber", "bInterfaceClass", "bNumEndpoints", "bcdDevice", "USB Product Name",
                     "USB Vendor Name", "kUSBProductString", "kUSBVendorString", "bcdUSB", "bMaxPacketSize0",
                     "bNumConfigurations", "Device Speed", "UsbDeviceSpeed"]
        var result: [String: String] = [:]
        func text(_ value: Any) -> String {
            switch value {
            case let number as NSNumber: number.stringValue
            case let string as String: string
            case let data as Data: data.map { String(format: "%02x", $0) }.joined()
            default: "\(value)".split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            }
        }
        for key in own {
            if let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                result[key] = text(value)
            }
        }
        for key in above {
            if let value = IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                                           IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) {
                result[key] = text(value)
            }
        }
        return result
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
                              onReport: { [weak self] bytes in
                                  guard let self, self.isEnabled(id), self.wantsReports() else { return }
                                  self.onReport(id, Array(bytes))
                              },
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

/// An IOHIDDevice handed to the queue that reads feature reports while the main queue keeps it open.
private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Report buffer of one open device; decodes on the main queue.
@MainActor
final class Reports {
    nonisolated(unsafe) let buffer: UnsafeMutablePointer<UInt8>
    private let model: SpaceMouseModel
    private let onReport: (UnsafeBufferPointer<UInt8>) -> Void
    private let onAxes: (SpaceMouseAxes) -> Void
    private let onButtons: (SpaceMouseButtons) -> Void
    private let onBattery: (Int, Bool) -> Void
    private var pending = SpaceMouseAxes.zero
    private var buttons: SpaceMouseButtons = []

    init(size: Int, model: SpaceMouseModel, onReport: @escaping (UnsafeBufferPointer<UInt8>) -> Void,
         onAxes: @escaping (SpaceMouseAxes) -> Void,
         onButtons: @escaping (SpaceMouseButtons) -> Void, onBattery: @escaping (Int, Bool) -> Void) {
        buffer = .allocate(capacity: size)
        self.model = model
        self.onReport = onReport
        self.onAxes = onAxes
        self.onButtons = onButtons
        self.onBattery = onBattery
    }

    deinit { buffer.deallocate() }

    func ingest(_ bytes: UnsafeBufferPointer<UInt8>) {
        onReport(bytes)
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
