// Reads vendor feature report 0x08 (GET only, nothing is written) of every attached SpaceMouse and prints it raw.
// The report holds the SpaceMouse Wireless's serial number (stagehand ADR-0092); docs/serial-report.md collects what
// it holds on the other models. Quit Space Juggler and the 3Dconnexion helper first, or the open fails
// (kIOReturnExclusiveAccess). Run: swift Scripts/read-serial-report.swift
import Foundation
import IOKit.hid

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
        print(label, String(format: "open failed (0x%08X)", UInt32(bitPattern: opened)))
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
