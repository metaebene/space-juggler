// Reads vendor feature report 0x08 (GET only, nothing is written) of every attached SpaceMouse and prints it raw.
// The report holds the SpaceMouse Wireless's serial number (stagehand ADR-0092); docs/serial-report.md collects what
// it holds on the other models. A device someone else holds (Space Juggler, the 3Dconnexion helper) cannot be opened;
// on USB the same GET then goes over the control pipe (GET_REPORT, nothing is opened). Run:
// swift Scripts/read-serial-report.swift
import Foundation
import IOKit.hid
import IOUSBHost

/// GET_REPORT for feature report 0x08 on interface 0 of the USB device at `location`, without opening its HID device.
func controlPipeReport(location: Int) -> String {
    let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
    matching[kIOPropertyMatchKey] = ["locationID": location]
    let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    guard service != 0 else { return "no USB device at this location" }
    defer { IOObjectRelease(service) }
    do {
        let usb = try IOUSBHostDevice(__ioService: service, options: [], queue: nil, interestHandler: nil)
        defer { usb.destroy() }
        var request = IOUSBDeviceRequest()
        request.bmRequestType = 0xA1    // class, interface, device to host
        request.bRequest = 0x01         // GET_REPORT
        request.wValue = 0x0308         // feature report 0x08
        request.wLength = 8
        let data = NSMutableData(length: 8)!
        var count = 0
        try usb.__send(request, data: data, bytesTransferred: &count, completionTimeout: 1)
        return [UInt8](Data(referencing: data).prefix(count)).map { String(format: "%02x", $0) }.joined(separator: " ")
            + " (control pipe)"
    } catch {
        return "control pipe failed: \(error.localizedDescription)"
    }
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDPrimaryUsagePageKey: 1, kIOHIDPrimaryUsageKey: 8] as CFDictionary)
let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
if devices.isEmpty { print("no SpaceMouse attached") }
for device in devices {
    func property(_ key: String) -> Any? { IOHIDDeviceGetProperty(device, key as CFString) }
    let label = String(format: "%04X:%04X %@ (%@)", property(kIOHIDVendorIDKey) as? Int ?? 0,
                       property(kIOHIDProductIDKey) as? Int ?? 0, property(kIOHIDProductKey) as? String ?? "?",
                       property(kIOHIDTransportKey) as? String ?? "?")
    let opened = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard opened == kIOReturnSuccess else {
        let usb = (property(kIOHIDTransportKey) as? String) == "USB"
        print(label, usb ? controlPipeReport(location: property(kIOHIDLocationIDKey) as? Int ?? 0)
                         : String(format: "open failed (0x%08X)", UInt32(bitPattern: opened)))
        continue
    }
    var buffer = [UInt8](repeating: 0, count: 8)
    buffer[0] = 0x08
    var length = CFIndex(buffer.count)
    let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0x08, &buffer, &length)
    IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    print(label, result == kIOReturnSuccess
          ? buffer.prefix(Int(length)).map { String(format: "%02x", $0) }.joined(separator: " ")
          : String(format: "GET failed (0x%08X)", UInt32(bitPattern: result)))
}
