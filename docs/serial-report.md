# Feature report 0x08 on the models other than the Wireless

The SpaceMouse Wireless carries its printed serial number in vendor feature report 0x08 (`08 5a 00 01 2b 7c 17 53` =
"Z5024520019", a letter and six bytes as one big-endian number; stagehand ADR-0092). None of the USB models has a
serial number string, so Space Juggler tells them apart only by model + USB port (ADR-0003). Whether report 0x08 can
do better for them is open; this file collects what it holds. Read with `swift Scripts/read-serial-report.swift`
(GET only; a USB device that someone else holds, such as Space Juggler or the 3Dconnexion helper, is read over the
control pipe instead).

## Descriptors (IORegistry, 2026-10-15)

The SpaceMouse Compact (256F:C635), the SpaceNavigator (046D:C626) and the SpaceMouse Pro (046D:C62B) all declare
report 0x08 exactly as the Wireless does: vendor page 0xFF00, usage 0x23, seven bytes (`85 08 09 23 95 07 b1 02`).

## Read at the devices

| Date | Model | Report 0x08 | Label |
|---|---|---|---|
| 2026-10-15 | SpaceMouse Compact 256F:C635, USB | `08 53 53 01 01 62 5f ac` | no serial number printed |
| 2026-10-15 | SpaceNavigator 046D:C626, USB | `08 ff ff ff ff ff ff ff` | no serial number printed |
| 2026-10-15 | SpaceNavigator 046D:C626, USB, a second device (other Mac) | `08 ff ff ff ff ff ff ff` | not compared |
| 2026-10-15 | SpaceMouse Pro 046D:C62B, USB | `08 00 00 00 00 00 00 00` | not compared |
| 2026-10-15 | SpaceMouse Compact 256F:C635, USB, a second device (other Mac) | `08 53 00 01 01 90 4f e5` | not compared |
| 2026-10-16 | SpaceTraveler 046D:C623, USB (Space Probe, issue #1) | `08 86 01 d5 0f 00 00 77` | "T30U31CX \*06241985\*" |
| 2026-10-17 | the same SpaceTraveler, second report | `08 86 01 d5 0f 00 00 77` | read as "T3oU32CX \*06241985\*" |

- SpaceNavigator: all 0xFF on both devices, nothing stored; it stays at model + USB port.
- SpaceMouse Pro: all zero, nothing stored; it stays at model + USB port.
- SpaceTraveler: filled, and the label has a serial number, but they do not match: 0x86 is no letter, and neither
  6241985 (0x5F3EC1) nor any other run of the label's digits appears in the bytes, big- or little-endian. Space Juggler
  does not ask 046D models for report 0x08 anyway; the SpaceTraveler stays at model + USB port. The same bytes on
both readings; the label was read differently the second time (only "\*06241985\*" is the same).
- SpaceMouse Compact: filled on both devices, and different. The first has two letters "SS", then five bytes: as one
  number 4318191532 ("SS4318191532"); the Wireless's decoding (one letter, six bytes) would give "S91263783296940".
  The second has "S", a zero byte, then five bytes: 4321202149 ("S4321202149", the same in both readings).
- One reading fits all three devices: up to two letters (a zero byte = none), then five bytes as one big-endian number.
  The Wireless's `5a 00` + `01 2b 7c 17 53` is "Z5024520019" in it too. The two Compacts' numbers lie 3 million apart,
  ten digits each like the Wireless's: that looks like serial numbers, not like a fixed value or a random one. Still
  not checked against a label.

## Decision (2026-10-15, Tim)

Report 0x08 is taken as the Compact's serial number: Space Juggler reads it like the Wireless's
(`SpaceMouseModel.serialFeatureReportID`) and decodes up to two letters (`SpaceMouseReport.serialNumber`), so a Compact
is `serial:S4321202149` instead of `port:256f:c635@…`, in the menu with its serial number, the same on every port. On
USB the GET goes over the control pipe when the HID device cannot be opened (3Dconnexion's helper seizes it), checked at
the second Compact with the helper running.

## Open

- A label or box with a Compact's serial number printed would confirm the format.
- SpaceNavigator and SpaceMouse Pro: report 0x08 is empty. Tim looks for a printed serial number on one of them, to
  search the device for it once more (string descriptors besides the absent `iSerialNumber`, for instance).
