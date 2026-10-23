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

    /// The USB port and interface of a device, for a GET on the control pipe; nil over Bluetooth.
    private typealias USBPath = (location: Int, interface: Int)

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
    /// Appeared, their serial number still being read off the main queue; one gone again before that finished is
    /// never registered.
    private var pending: Set<UInt64> = []
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
        guard let (key, entry) = lookup(id) else { return "no such device" }
        if entry.model.statusLEDNeedsCable, entry.info.isBluetooth { return "the LED lights only on the USB cable" }
        var report: [UInt8] = [4, on ? 1 : 0]
        let result = Self.withDevice(key, open: entry.device, options: IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) { device in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 4, &report, report.count)
        }
        guard let result else { return "device busy" }
        guard result == kIOReturnSuccess else { return String(format: "LED not switched (0x%08X)", UInt32(bitPattern: result)) }
        entries[key]?.info.led = on
        onChange()
        return nil
    }

    /// The listed device with this identity (ADR-0003), with its key.
    private func lookup(_ id: String) -> (key: UInt64, entry: Entry)? {
        entries.first { $0.value.info.id == id }.map { ($0.key, $0.value) }
    }

    /// The model a listed device was recognised as.
    func model(of id: String) -> SpaceMouseModel? { lookup(id)?.entry.model }

    private func appeared(_ managed: IOHIDDevice) {
        func property(_ key: String) -> Any? { IOHIDDeviceGetProperty(managed, key as CFString) }
        guard let key = Self.registryID(of: managed), entries[key] == nil, !pending.contains(key),
              let vendor = property(kIOHIDVendorIDKey) as? Int, let product = property(kIOHIDProductIDKey) as? Int else { return }
        let transport = property(kIOHIDTransportKey) as? String ?? SpaceMouseDevice.usbTransport
        // 3Dconnexion's driver publishes virtual devices of its own (docs/3dxware-package.md): never a SpaceMouse.
        guard !transport.localizedCaseInsensitiveContains("virtual") else { return }
        let descriptor = (property(kIOHIDReportDescriptorKey) as? Data).flatMap { HIDReportDescriptor([UInt8]($0)) }
        guard let model = SpaceMouseModel.recognise(vendorID: vendor, productID: product,
                                                    product: property(kIOHIDProductKey) as? String, descriptor: descriptor) else { return }
        // The identity (`id`) follows once the serial number is known (`register`).
        let info = SpaceMouseDevice(id: "", vendorID: vendor, productID: product, name: model.name, transport: transport,
                                    serialNumber: (property(kIOHIDSerialNumberKey) as? String)?.nonEmpty,
                                    bluetoothAddress: (property("DeviceAddress") as? String)?.nonEmpty,
                                    locationID: property(kIOHIDLocationIDKey) as? Int ?? 0,
                                    knowledge: model.knowledge, buttons: model.buttons, axisFullScale: model.axisFullScale,
                                    hasLED: model.hasStatusLED)
        let interface = Self.interfaceNumber(of: IOHIDDeviceGetService(managed))
        guard info.serialNumber == nil, let reportID = model.serialFeatureReportID else {
            return register(key, model: model, info: info, interface: interface)
        }
        // The serial number (ADR-0003): a GET takes a round trip over Bluetooth, so off the main queue.
        pending.insert(key)
        let usb = Self.usbPath(of: info, interface: interface)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let serial = Self.readFeature(key, reportID: reportID, length: 8, device: nil, usb: usb)
                .flatMap { SpaceMouseReport.serialNumber($0.bytes) }
            Task { @MainActor in
                guard let self, self.pending.remove(key) != nil else { return }
                var info = info
                info.serialNumber = serial
                self.register(key, model: model, info: info, interface: interface)
            }
        }
    }

    private func register(_ key: UInt64, model: SpaceMouseModel, info: SpaceMouseDevice, interface: Int?) {
        guard entries[key] == nil else { return }
        var info = info
        info.id = Self.identity(of: info, slot: info.productID == SpaceMouseModel.universalReceiverProductID ? interface : nil)
        entries[key] = Entry(info: info, model: model, interface: interface)
        log("device appeared: \(model) \(info.id) (\(info.transport))")
        if wanted { open(key) }
        onChange()
    }

    /// Serial number, else Bluetooth address, else model + USB port (ADR-0003), and the slot on a Universal Receiver
    /// (ADR-0005).
    nonisolated static func identity(of device: SpaceMouseDevice, slot: Int? = nil) -> String {
        if let serial = device.serialNumber { return "serial:\(serial)" }
        if device.isBluetooth, let address = device.bluetoothAddress?.nonEmpty {
            return "bt:\(address.lowercased().replacingOccurrences(of: "-", with: ":"))"
        }
        return String(format: "port:%04x:%04x@%08x", device.vendorID, device.productID, device.locationID ?? 0)
            + (slot.map { "/\($0)" } ?? "")
    }

    private nonisolated static func usbPath(of device: SpaceMouseDevice, interface: Int?) -> USBPath? {
        device.isUSB ? (device.locationID ?? 0, interface ?? 0) : nil
    }

    /// The `bInterfaceNumber` of the USB interface a HID device sits on; nil over Bluetooth.
    private nonisolated static func interfaceNumber(of service: io_service_t) -> Int? {
        IORegistryEntrySearchCFProperty(service, kIOServicePlane, "bInterfaceNumber" as CFString, kCFAllocatorDefault,
                                        IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? Int
    }

    // MARK: - Feature reports (GET only)

    /// Runs `body` with `open` when the device is open already, else with a device object of our own, opened with
    /// `options` for the call and closed again; nil when that open fails.
    private nonisolated static func withDevice<Result>(_ key: UInt64, open: IOHIDDevice?, options: IOOptionBits,
                                                       body: (IOHIDDevice) -> Result) -> Result? {
        if let open { return body(open) }
        guard let own = ownDevice(key), IOHIDDeviceOpen(own, options) == kIOReturnSuccess else { return nil }
        defer { IOHIDDeviceClose(own, IOOptionBits(kIOHIDOptionsTypeNone)) }
        return body(own)
    }

    /// A feature report, report ID first: through the HID device (`open`, else one of our own, opened without
    /// seizing), on USB else as a class request on the control pipe, for a device someone else holds (3Dconnexion's
    /// helper seizes every SpaceMouse, so opening its HID device fails). Nil when every way fails; `via` says which
    /// worked.
    private nonisolated static func readFeature(_ key: UInt64, reportID: UInt8, length: Int, device open: IOHIDDevice?,
                                                usb: USBPath?) -> (bytes: [UInt8], via: String)? {
        if let bytes = getFeature(key, reportID: reportID, length: length, device: open) { return (bytes, "HID device") }
        guard let usb, let bytes = getFeatureOverControlPipe(usb, reportID: reportID, length: length) else { return nil }
        return (bytes, "control pipe")
    }

    private nonisolated static func getFeature(_ key: UInt64, reportID: UInt8, length: Int, device open: IOHIDDevice?) -> [UInt8]? {
        withDevice(key, open: open, options: IOOptionBits(kIOHIDOptionsTypeNone)) { device -> [UInt8]? in
            var buffer = [UInt8](repeating: 0, count: max(length, 2))
            buffer[0] = reportID
            var count = CFIndex(buffer.count)
            guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), &buffer, &count) == kIOReturnSuccess else {
                return nil
            }
            return Array(buffer.prefix(Int(count)))
        } ?? nil
    }

    /// Nothing is opened or written: a GET_REPORT on the default pipe.
    private nonisolated static func getFeatureOverControlPipe(_ usb: USBPath, reportID: UInt8, length: Int) -> [UInt8]? {
        let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        matching[kIOPropertyMatchKey] = ["locationID": usb.location]
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let device = try? IOUSBHostDevice(__ioService: service, options: [], queue: nil, interestHandler: nil) else {
            return nil
        }
        defer { device.destroy() }
        var request = IOUSBDeviceRequest()
        request.bmRequestType = 0xA1                        // class request to an interface, device to host
        request.bRequest = 0x01                             // GET_REPORT
        request.wValue = 0x0300 | UInt16(reportID)          // feature report
        request.wIndex = UInt16(usb.interface)
        request.wLength = UInt16(max(length, 2))
        let data = NSMutableData(length: max(length, 2))!
        var count = 0
        guard (try? device.__send(request, data: data, bytesTransferred: &count, completionTimeout: 1)) != nil else { return nil }
        return [UInt8](Data(referencing: data).prefix(count))
    }

    /// Everything that can be read about a device without changing it (ADR-0006), off the main queue.
    func describe(_ id: String, completion: @escaping @MainActor (DeviceDescription) -> Void) {
        guard let (key, entry) = lookup(id) else { return completion(DeviceDescription(device: id, error: "no such device")) }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(key))
        guard service != 0 else { return completion(DeviceDescription(device: id, error: "not in the IORegistry")) }
        defer { IOObjectRelease(service) }
        let properties = Self.properties(of: service)
        let bytes = (IORegistryEntryCreateCFProperty(service, kIOHIDReportDescriptorKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data).map { [UInt8]($0) } ?? []
        let features = HIDReportDescriptor(bytes)?.reports.filter { $0.kind == .feature } ?? []
        let finish: @Sendable ([DeviceDescription.FeatureReport], String?) -> DeviceDescription = {
            DeviceDescription(device: id, properties: properties, reportDescriptor: bytes, featureReports: $0, featureReportsVia: $1)
        }
        if let open = entry.device {
            // Our open device object stays on the main queue, its dispatch queue and where close() runs; one GET per
            // turn of the queue, so input and other clients get between them. We hold it: no control-pipe fallback.
            Task { @MainActor in
                var via: String?
                var reports: [DeviceDescription.FeatureReport] = []
                for report in features {
                    reports.append(Self.featureReport(key, report, device: open, usb: nil, via: &via))
                    await Task.yield()
                }
                completion(finish(reports, via))
            }
        } else {
            // Nothing of ours is open: device objects of our own, off the main queue (a round trip per report).
            let usb = Self.usbPath(of: entry.info, interface: entry.interface)
            DispatchQueue.global(qos: .userInitiated).async {
                var via: String?
                let reports = features.map { Self.featureReport(key, $0, device: nil, usb: usb, via: &via) }
                let description = finish(reports, via)
                Task { @MainActor in completion(description) }
            }
        }
    }

    /// One feature report for a description; `via` keeps the first way that worked.
    private nonisolated static func featureReport(_ key: UInt64, _ report: HIDReportDescriptor.Report, device: IOHIDDevice?,
                                                  usb: USBPath?, via: inout String?) -> DeviceDescription.FeatureReport {
        guard let read = readFeature(key, reportID: report.id, length: report.length, device: device, usb: usb) else {
            return .init(id: Int(report.id), error: "GET failed")
        }
        via = via ?? read.via
        return .init(id: Int(report.id), bytes: read.bytes)
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
            case let data as Data: data.hex(separator: "")
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

    // MARK: - Opening and closing

    private func vanished(_ managed: IOHIDDevice) {
        guard let key = Self.registryID(of: managed) else { return }
        pending.remove(key)
        guard let entry = entries[key] else { return }
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
            cancel(device, keeping: reports)
            let busy = result == kIOReturnExclusiveAccess
            let state = busy ? "busy" : String(format: "open failed (0x%08X)", UInt32(bitPattern: result))
            entries[key]?.info.state = state
            if entry.attempt == 0 { log("seize \(id): \(state)") }
            // Another process still holds it (a broker handing over closes first): retry for 2 s.
            if busy, entry.attempt < 20 {
                entries[key]?.attempt += 1
                MainActor.after(0.1) { [weak self] in
                    guard let self, wanted else { return }
                    open(key)
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
        guard let entry = entries[key], let device = entry.device, let reports = entry.reports else { return }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        cancel(device, keeping: reports)
        entries[key]?.device = nil
        entries[key]?.reports = nil
        entries[key]?.info.state = "closed"
        log("released \(entry.info.id)")
        onChange()
    }

    /// Cancels a device object; it and its report buffer live until the cancel handler ran, as IOKit may still
    /// deliver into the buffer.
    private func cancel(_ device: IOHIDDevice, keeping reports: Reports) {
        IOHIDDeviceSetCancelHandler(device) { withExtendedLifetime((device, reports)) {} }
        IOHIDDeviceCancel(device)
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
