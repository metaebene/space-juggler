# SpaceMouse models: what is known, and from where

Desk research, 2026-10-15: every 3Dconnexion / Logitech-era 6DoF device a macOS HID broker may meet. Only public
sources: open-source code (read for facts, no code taken), raw `lsusb` and hex dumps, public manuals and FAQ pages.
Nothing from the manufacturer's SDK headers. This is the map, not the truth: what is in `SpaceMouseKit` is what was
checked at a device.

**Knowledge:** **D** checked at a device here · **H** source code or a raw dump · **M** several consistent reports or
a public manual · **L** a single post.

## Overview

Axes "split" = report 1 (x y z) and report 2 (rx ry rz), seven bytes each with the ID; "combined" = one report 1 of
thirteen bytes. Keys = physical keys; the button report is report 3.

| Device | VID:PID | Transport | Keys | Axes | Button report | Knowledge |
|---|---|---|---|---|---|---|
| SpaceMouse Plus / Plus XT USB | 046D:C603 | USB | 9–11 (disputed) | ? | ? | L |
| CadMan USB | 046D:C605 | USB | 4 (disputed) | ? | ? | L |
| SpaceMouse Classic USB | 046D:C606 | USB 1.1 | 8 + "*" | ? | ? | L |
| Spaceball 5000 USB | 046D:C621 | USB | 12 (13 usages) | split, ±500 | 13 bits, 2 B | H (descriptor) |
| SpaceTraveler | 046D:C623 | USB | 8 | split, ±500 | 1 B, bits 0–7 | **D** (descriptor, axes, LED; keys open) |
| SpacePilot | 046D:C625 | USB | 21 + LCD | split | bits 0–20 | M/H |
| **SpaceNavigator** | 046D:C626 | USB | 2 | split, ±500 here (±350 in public dumps) | 2 bits | **D** |
| SpaceExplorer | 046D:C627 | USB | 15 | split | bits 0–14 | H |
| SpaceNavigator for Notebooks | 046D:C628 | USB | 2 | split | 2 bits | H |
| SpacePilot Pro | 046D:C629 | USB, 2 interfaces | 31 + colour LCD | split | bits 0–30 | H/M |
| **SpaceMouse Pro** | 046D:C62B | USB | 15 | split, ±350 | 6 B, bits 0–26 | **D** |
| "Lipari" (?) | 256F:C62C | ? | ? | ? | ? | L (name only) |
| SpaceMouse Wireless (cable) | 256F:C62E | USB | 2 | combined, ±350 | 2 B | H |
| SpaceMouse Wireless receiver | 256F:C62F | 2.4 GHz dongle | 2 | combined, ±350 | 2 B | H |
| SpaceMouse Pro Wireless (cable) | 256F:C631 | USB | 15 | combined (assumed) | 6 B | M |
| SpaceMouse Pro Wireless receiver | 256F:C632 | 2.4 GHz dongle | 15 | combined | 7 B | M/H |
| SpaceMouse Enterprise | 256F:C633 | USB, 2 interfaces | 31 + colour LCD | combined | long (bits to 175) + 0x1C/0x1D | H/M |
| **SpaceMouse Compact** | 256F:C635 | USB | 2 | split, ±350 | 2 B | **D** |
| SpaceMouse Module (OEM) | 256F:C636 | USB | 0 | "standard joystick", 10 bit | – | L/M |
| SpaceMouse Pro Wireless BT | 256F:C638 | cable and Bluetooth, one PID | 15 | combined (assumed) | 6 B | M |
| **SpaceMouse Wireless BT** | 256F:C63A | cable and Bluetooth, one PID | 2 | combined, ±350 | 2 B | **D** |
| "SpaceMouse USB" / Module USB | 256F:C641 | USB | 0 | split | none | L, names conflict |
| Universal Receiver | 256F:C652 | 2.4 GHz dongle, 5 HID interfaces | per paired device | per paired device | per paired device | H/M |
| NuLOOQ (not a SpaceMouse) | 046D:C640 | USB | ? | ? | ? | L |

**Not 6DoF, to be ignored:** CadMouse 256F:C650, CadMouse Wireless C651, CadMouse Pro Wireless C654, CadMouse Compact
C655, CadMouse Pro C656, CadMouse Pro Wireless Left C657, CadMouse Compact Wireless C658, Keyboard Pro C664, Numpad Pro
C665, C668 (CadMouse Pro Wireless USB-C or a newer Keyboard Pro; sources disagree), "3Dconnexion Virtual Mouse" C671
(made by the macOS 3Dconnexion driver, with a virtual keyboard 05AC:0250). No public source names C639, C63B, C653,
C659, C666, C667.

**Recognising a 6DoF device without knowing its PID:** Generic Desktop / Multi-axis Controller (usage page 1, usage
8), vendor 046D or 256F. On macOS the Universal Receiver's SpaceMouse slot has vendor page 0xFF00 as its *primary*
usage; 1/8 is only in `DeviceUsagePairs` (consi/axial PR #6), so match the pairs, not `PrimaryUsage`. spacenavd treats
every 256F device as 6DoF unless blacklisted and drops interfaces without axes.

## Reports shared by all models

- **Report 1 / 2, axes.** int16 little-endian. Split or combined; Blender, OpenSCAD and Open CASCADE tell them apart by
  the report's length (13 = combined), not by PID. Windows pads every input report to the longest one; hidraw gives the
  real length.
- **Axis range.** Every public descriptor says ±350, the Spaceball 5000 ±500. Our SpaceNavigator's descriptor says ±500
  (IORegistry, 2026-10-04); the public SpaceNavigator dumps (three firmware variants, 202/217/228 B) say ±350. Open
  CASCADE switches to a ±32767 scale when it sees more than 350; OpenSCAD notes "−2595..2595 at max speed". Take the
  descriptor's logical maximum per device, clamp defensively.
- **Relative flag.** SpaceNavigator, SpaceTraveler, Spaceball 5000 and SpaceMouse Pro declare their axes Relative
  (`81 06`) though the values are absolute (Linux `hid-lg` and udev-hid-bpf patch it). C62E and later say Absolute.
  Read raw reports, never `IOHIDValue`'s relative semantics.
- **Report 3, buttons.** Bit n = HID button usage n+1. 2 B on the two-button models, 6 B on the Pro family (7 B seen
  through a receiver), 22+ B on the Enterprise. The numbering is shared across models (see the Pro, SpacePilot Pro and
  Enterprise tables): the same bit is the same key wherever it exists.
- **Report 4, LED (output).** Usage page 0x08 / 0x4B, one bit: `04 01` on, `04 00` off. spacenavd switches it on then off
  at start because a Compact "fails to turn the LED off unless turned on first". The Spaceball 5000 has no LED report;
  PySpaceMouse says the SpacePilot and C641 have none; the SpaceExplorer does not light it after plug-in.
- **Report 0x17, battery (input).** Three bytes: percent (usage 0x06:0x20), then one vendor bit (0xFF00:0x27), probably
  "charging / on cable" (`17 64 01` on cable, `17 64 00` / `17 30 01` from a receiver; inferred). Seen on C62E, C62F,
  Universal Receiver slots, C63A.
- **Report 0x1C / 0x1D, key codes (input).** Enterprise, Keyboard Pro, Numpad Pro: up to six uint16 LE key codes, 0x1C
  short press, 0x1D long press; code = report-3 bit + 1. Long presses carry the secondary functions (T→bottom, R→left,
  F→back, roll→reverse roll, ISO1→ISO2, V1–V3 → save).
- **Vendor feature reports** on page 0xFF00, 8-bit fields: 0x05–0x07 (1 B), 0x08–0x0A (7 B), 0x0B (1 B), 0x13 (1 B),
  0x19 (4 B, newer SpaceNavigator firmware, C62E), 0x1A (7 B, C62E), 0x14/0x15 (Pro). No public description of any of
  them. **0x08 as serial number is our finding** (docs/serial-report.md); nobody else documents it.
- **Feature reports read at a Compact** (256F:C635, fw 1079, `space-juggler-cli describe`, 2026-10-15): 0x06 `06 03`,
  0x08 the serial number, 0x09 `09 80 78 79 82 81 7e 7f` and 0x0A `0a ba be bb b8 bc c2 bf` (seven values each, near
  128 and near 190: per-axis calibration?), 0x13 `13 1a`, 0x1A all zero; GET fails for 0x05, 0x07, 0x0B and 0x19.
- **Feature reports read at a SpaceTraveler** (046D:C623, fw 0x0311, Space Probe, issue #1, 2026-10-16): it declares
  only 0x05–0x0B. 0x06 `06 03` as on the Compact, 0x08 `08 86 01 d5 0f 00 00 77` (filled, but not the label's serial
  number in any reading tried, docs/serial-report.md), 0x09 `09 7f 7f 7f 7a 80 81 7d` and 0x0A
  `0a 7e 81 7e 7f 7a 78 bf` (near 128 again, 0x0A's last byte near 190 as on the Compact); GET fails for 0x05, 0x07
  and 0x0B, as on the Compact.
- **USB serial string:** none on any real device found (iSerialNumber 0), on any model. Over Bluetooth the C63A has its
  Bluetooth address as the unique ID.
- **Axis orientation:** spacenavd swaps and negates y/z for all 256F devices and for 046D C605, C621, C623, C625–C62B,
  not for C603, C606, C640 — those older ones may differ from our signs.

## Per model

**SpaceNavigator C626 / for Notebooks C628** (2006–2020). Three descriptor variants: 202 B (fw 3.18/4.04), 217 B
(4.14–4.35), 228 B (4.36, adds feature 0x19). Firmware 4.20+ has an interrupt OUT endpoint. Strings "3Dconnexion" /
"SpaceNavigator" ("SpaceNavigator for Notebooks"). Reports 1 and 2 alternate every 8 ms. Two keys, bits 0/1.

**SpaceTraveler C623** — first report from Space Probe (github.com/metaebene/space-juggler/issues/1, 2026-10-16;
label "SpaceTraveler3 USB", USB name "SpaceTraveler USB", bcdDevice 0x0311, low speed, macOS 15.8, no 3Dconnexion
driver running). Descriptor 204 B: split axes in reports 1 and 2, logical ±500 (physical −32768 … 32767), declared Relative;
report 3 one byte for HID buttons 1–8 plus a padding byte; output report 4 with two LED usages (0x4B, 0x4C), one bit
each; vendor features 0x05–0x0B, nothing beyond. All twelve directions moved the expected axis with our signs (peaks
263–424 of 500). The LED lit with `04 01` and went out with `04 00`. All eight declared buttons seen, bits 0–7. The keys are
not printed (the reporter, 2026-10-16): eight keys round the cap, the USB cable at 12 o'clock. They were pressed from the
one at 1–2 o'clock clockwise, but the report (Space Probe 0.4) sorted them by bit, so which bit sits where is still
open; since then the report keeps the order pressed. 3DxWare calls them buttons 1–8 (3Dconnexion forum, "SpaceTraveler
problems with button 8"), so `SpaceMouseKit` names bit n key n+1. The reporter's old 3DxWare knew only two of them,
"L" and "R", guessed to be the keys left and right of the cable (8 and 1 in the clockwise count).

**SpaceExplorer C627** (2007–2016). 15 keys, bits agreed by Blender, PySpaceMouse, FreeCAD and Open CASCADE:
0 `1`, 1 `2`, 2 T, 3 L, 4 R, 5 F, 6 ESC, 7 ALT, 8 SHIFT, 9 CTRL, 10 FIT, 11 PANEL, 12 `+`, 13 `−`, 14 2D.
Its own numbering, not the shared one.

**SpacePilot C625** (2005). 21 keys, an LCD with six soft keys, one HID interface (so any LCD traffic is HID; no open
project drives it). Bits: 0–5 keys 1–6, 6 T, 7 L, 8 R, 9 F, 10 ESC, 11 ALT, 12 SHIFT, 13 CTRL, 14 FIT, 15 MENU,
16 `+`, 17 `−` (16/17 swapped in PySpaceMouse), 18 DOMINANT, 19 3D lock, 20 CONFIG.

**SpacePilot Pro C629** (2009). 31 keys, colour LCD. Interface 0 vendor class with bulk endpoints (the LCD, no open
driver), interface 1 HID with split axes. Shared numbering: 0 MENU, 1 FIT, 2 T, 3 L, 4 R, 5 F, 6 B, 7 BK, 8 roll CW,
9 roll CCW, 10 ISO1, 11 ISO2, 12–21 keys 1–10, 22 ESC, 23 ALT, 24 SHIFT, 25 CTRL, 26 ROTATE, 27 PAN/ZOOM,
28 DOMINANT, 29 `+`, 30 `−` (PySpaceMouse disagrees on keys 1–5; likely its error).

**SpaceMouse Pro C62B** — in `SpaceMouseKit`, checked at a device (stagehand ADR-0087). Public sources agree
(Blender mask 0x07C0F137). Descriptor 312 B (fw 4.35) or 334 B (fw 4.37).

**SpaceMouse Wireless C62E / C62F** (2013). Two keys, combined axes at ±350 every ~16 ms, battery 0x17, LED 4. The same
HID data on cable and receiver. Full descriptor decode: AndunHH/spacemouse `SpaceMouseWireless.md`. Later packages
ship the Universal Receiver instead of C62F.

**SpaceMouse Pro Wireless C631 / C632** (2014). The Pro's keys and bits, combined axes, report 3 of seven bytes through
the receiver (`03 00 10 00 00 00 00` = key 1, bit 12). Battery, hand-presence sensor. Before 2019 its own receiver,
then the Universal Receiver. Nobody has dumped C631 traffic.

**BT editions C638 (Pro Wireless BT, 2023) / C63A (Wireless BT, 2024).** One PID on cable and Bluetooth. They also pair
with the Universal Receiver (unpair there before Bluetooth). LED: white 2.4 GHz, blue Bluetooth, green/red battery.
C63A in `SpaceMouseKit` (stagehand ADR-0090–0092); C638 not seen over Bluetooth on macOS by anyone.

**SpaceMouse Enterprise C633** (2016). 31 keys: 1–12 (with LCD labels), ESC, ENTER, TAB, SHIFT, CTRL, ALT, SPACE,
DELETE, MENU, FIT, V1–V3, five QuickView keys with long-press secondaries, LOCK. Interface 0 vendor bulk (the LCD),
interface 1 HID, combined axes. Report-3 bits (spacenavd, PySpaceMouse, sixdof): 0 MENU, 1 FIT, 2 T, 4 R, 5 F,
8 roll, 10 ISO, 12–21 keys 1–10, 22 ESC, 23 ALT, 24 SHIFT, 25 CTRL, 26 LOCK, 35 ENTER, 36 DEL, 76/77 keys 11/12,
102–104 V1–V3, 174 TAB, 175 SPACE. Long presses only in 0x1C/0x1D. LCD 640×150 BGR565, raw-DEFLATE frames on bulk OUT,
backlight via feature 0x11; driven by the open SpaceLCD project.

**SpaceMouse Compact C635** (2018) — in `SpaceMouseKit`, checked at a device. Split axes, unlike the other 256F devices.
On macOS an extra "Virtual Mouse" interface appears while the 3Dconnexion helper runs; sixdof skips a mouse interface
(usage 1/2) on it.

**SpaceMouse Module C636 / C641.** OEM panel puck, "standard USB joystick, 6 axes, 10 bit", no keys, not supported by
3DxWare. C641's name is disputed.

**Spaceball 5000 USB C621.** Full descriptor public: split ±500, Relative, 13 button usages (12 printed), features
0x05–0x0B, no LED.

**Legacy serial devices** (Spaceball 1003–5000FLX, Magellan / SpaceMouse Classic / Plus serial). Not HID; out of scope.

**Universal Receiver C652.** Up to five pairings (SpaceMouse Wireless, Pro Wireless 2019+, both BT editions, wireless
CadMice, Keyboard Pro). Five HID interfaces, one per slot, 32-byte IN, no OUT endpoint. **Multiplexed by interface, not
by prefix**: a slot's reports are byte-identical to the paired device's own. The slot's descriptor shows what is paired:
129 B empty, 448 B SpaceMouse Wireless, 543 B Pro Wireless, 389/391 B CadMouse. Slot order varies; open all five and
choose by descriptor. No public feature report names the paired model or its serial number (spacenavd guesses Pro
Wireless from more than two buttons; Blender assumes Pro Wireless).

## Conflicts

1. SpacePilot bits 16/17: `+`/`−` (Blender, Open CASCADE, FreeCAD, spacenavd) or swapped (PySpaceMouse).
2. SpacePilot Pro keys 1–5: bits 12–16 (Blender, Open CASCADE) or 14–18 (PySpaceMouse).
3. Enterprise keys 11/12: bits 76/77 (spacenavd, sixdof; Blender's key codes 77/78 agree) or key codes 72/73 (FreeCAD).
4. C658: CadMouse Compact Wireless (FAQ, spacenavd) or a receiver PID (Blender, contradicted by its own issue).
5. C641 and C62C: names unclear.
6. SpaceNavigator axis range: ±500 here, ±350 in public dumps — firmware, or something the driver writes?
7. Old devices' key counts (Plus/Plus XT, CadMan, Spaceball 5000's 13th usage).

## Open at the device

What no public source answers, and what a probe run at someone's device has to collect:

- Report descriptors of C625, C627, C629, C631, C633, C638 and the Universal Receiver's slots; their axis range and
  split/combined.
- Report 0x08 on every model, compared with the label: is it the serial number everywhere?
- Whether the Universal Receiver tells which device is paired in a slot, and that device's serial number.
- Battery report and its second byte on C631, C632, C638, and over the Universal Receiver.
- Every key of the SpaceExplorer, SpacePilot, SpacePilot Pro and Enterprise, to settle the conflicts above.
- The SpaceTraveler's keys: which bit each of the eight (unprinted, round the cap) sets.
- Axis signs on the 046D models spacenavd treats differently (C603, C606).
- The LED: which models light it, and the Compact's on-before-off behaviour.

## Consequences for SpaceMouseKit

- `SpaceMouseButtons` is a `UInt32`; the Enterprise needs bits up to 175, the SpacePilot Pro up to 30 in the shared
  numbering. The button set needs to grow (or be keyed by bit number).
- Split vs combined by the report's length, as today; the axis range from the descriptor, per device.
- Recognise unknown devices by usage 1/8 in `DeviceUsagePairs`, so a new model shows up (axes and raw button bits)
  before it is in the catalog.
- The Universal Receiver is five devices in one, and none of them has a serial number of its own (so far).

## Sources

**Device reports:** Space Probe reports as GitHub issues on metaebene/space-juggler (#1: SpaceTraveler).

**Code:** Blender `intern/ghost/intern/GHOST_NDOFManager.cc`, `GHOST_SystemWin32.cc` (processNDOF), issues #82412,
#116393, #119206, PR !124155 · spacenavd `src/dev.c`, `src/dev_usb_linux.c`, `src/dev_usb_freebsd.c`,
`src/dev_serial.c`, issues #4, #12, #85, #90, #119, PRs #39, #134 · PySpaceMouse `pyspacemouse/devices.toml`, issues
#16, #28, #33, #35, #37, #42, #49 · OpenSCAD `src/gui/input/HidApiInputDriver.cc`, PR #2734 (hidapi logs), issue #5153 ·
FreeCAD `src/Gui/3Dconnexion/GuiNativeEventWin32.cpp` · Open CASCADE `WNT_HIDSpaceMouse.cxx` · Linux
`drivers/hid/hid-ids.h`, `hid-lg.c`, `hid-quirks.c` · udev-hid-bpf `0010-Logitech__SpaceNavigator.bpf.c` and its
SpaceNavigator case study · SpaceLCD (github.com/TheHoodedFoot/SpaceLCD) · AndunHH/spacemouse `SpaceMouseWireless.md`,
`SpaceNavigator.md` · jfedor2/magellan-spacemouse · consi/axial PR #6 · CloudCompare PR #2339 · PrusaSlicer
`Mouse3DController.cpp`, issue #15436 · spnavcfg #45, #60, #63 · gilbertorconde/sixdof (low weight).

**Dumps:** linuxhw/LsUSB (170 3Dconnexion dumps), usb.ids (linux-usb.org).

**Public vendor pages:** 3Dconnexion FAQ on recognising USB devices under Windows (web.archive.org); user manuals at
3dconnexion.com/manuals (SpaceMouse Enterprise, Pro, Pro Wireless, Wireless, Compact, BT editions); SpaceMouse Module
spec 3DX-700048.
