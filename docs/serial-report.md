# Feature report 0x08 on the models other than the Wireless

The SpaceMouse Wireless carries its printed serial number in vendor feature report 0x08 (`08 5a 00 01 2b 7c 17 53` =
"Z5024520019", a letter and six bytes as one big-endian number; stagehand ADR-0092). None of the USB models has a
serial number string, so Space Juggler tells them apart only by model + USB port (ADR-0003). Whether report 0x08 can
do better for them is open; this file collects what it holds. Read with `swift Scripts/read-serial-report.swift`
(GET only, Space Juggler and the 3Dconnexion helper not holding the device).

## Descriptors (IORegistry, 2026-10-15)

The SpaceMouse Compact (256F:C635) and the SpaceNavigator (046D:C626) both declare report 0x08 exactly as the Wireless
does: vendor page 0xFF00, usage 0x23, seven bytes (`85 08 09 23 95 07 b1 02`).

## Read at the devices

| Date | Model | Report 0x08 | Label |
|---|---|---|---|
| 2026-10-15 | SpaceMouse Compact 256F:C635, USB | `08 53 53 01 01 62 5f ac` | no serial number printed |
| 2026-10-15 | SpaceNavigator 046D:C626, USB | `08 ff ff ff ff ff ff ff` | no serial number printed |

- SpaceNavigator: all 0xFF, nothing stored; it stays at model + USB port.
- SpaceMouse Compact: filled, but not in the Wireless's format. Two letters "SS", then five bytes: as one number
  4318191532 ("SS4318191532"). The Wireless's decoding (one letter, six bytes) would give "S91263783296940". Neither
  can be checked against a label.

## Open

Cross-check with a second Compact and a second SpaceNavigator: if the Compact's bytes differ between two devices and
keep the "SS" + five bytes shape, report 0x08 is a unique ID (and probably the serial number) and Space Juggler can use
it as the Compact's identity; if they are identical or the SpaceNavigator's are filled after all, decide again. Until
then only the Wireless's report is read (`SpaceMouseModel.serialFeatureReportID`).
