# ADR-0005: A SpaceMouse the catalog does not know is still a SpaceMouse

- Status: proposed (2026-10-15)
- Date: 2026-10-15
- Related: ADR-0001 (model knowledge only in `SpaceMouseKit`), ADR-0003 (identity); `docs/models.md`

## Context

- Space Juggler opened only the four models checked at a device (Compact, SpaceNavigator, SpaceMouse Pro, SpaceMouse
  Wireless BT), matched by vendor and product ID. Every other SpaceMouse stayed invisible, also to a probe that could
  find out what it is.
- Public sources (`docs/models.md`) describe about twenty more: their IDs, mostly their keys, and the report layout all
  of them share (axes in report 1 and 2 or one long report 1, buttons in report 3, LED in output report 4). Nobody here
  has checked them at a device.
- A HID device describes its reports itself (report descriptor). What it does not say is which bit is which printed
  key, and what the vendor reports hold.
- 3Dconnexion numbers the keys of its bigger models in one scheme: bit 12 is key 1 and bit 22 ESC on the SpaceMouse Pro,
  the SpacePilot Pro and the Enterprise alike. The Enterprise goes up to bit 175 (TAB, SPACE); `SpaceMouseButtons` had
  32 bits for 17 named buttons.

## Decision

- **Recognised by what it is.** Space Juggler takes every HID device of vendor 046D or 256F that has the usage pair
  Generic Desktop / Multi-axis Controller (1/8) anywhere in `DeviceUsagePairs` (the Universal Receiver's slots have a
  vendor usage as their primary one), except the product IDs `SpaceMouseModel.ignored` lists (CadMice, keyboards,
  3Dconnexion's virtual devices) and virtual transports.
- **Catalog entries say how they are known** (`SpaceMouseModel.Knowledge`): `checked` at a device here, `published`
  (from public sources, `docs/models.md`), or `guessed` for a product ID the catalog lacks. A guessed model is built
  from its report descriptor: its name from the device, the axis range from the logical maximum, two buttons as left
  and right, more as 3Dconnexion's shared numbering.
- **The report descriptor is parsed in `SpaceMouseKit`** (`HIDReportDescriptor`, pure): reports, their lengths, axis
  range, button usages, LED report, feature reports.
- **One button set for all models**: `SpaceMouseButtons` grows to 64 bits and names every key of the shared numbering
  (keys 1–12, the views with their reverse sides, ENTER, DELETE, TAB, SPACE, V1–V3, `+`, `−`, DOMINANT, PAN/ZOOM,
  CONFIG). A model maps its bits onto it; the Enterprise's bits beyond 64 are read too.
- **The axis range belongs to the model** (`axisFullScale`): 350, the SpaceNavigator's descriptor says 500.
- **The Universal Receiver** (256F:C652) is one device per pairing slot; a slot's identity is the port and its USB
  interface number, until the paired device's serial number can be read.
- **A serial number** is asked for with feature report 0x08 on every 256F model except the Universal Receiver
  (all-zero or all-0xFF is none).
- Clients of protocol 1 get only the first 32 bits of the button set.

## Consequences

- A user with a SpaceMouse nobody here owns gets its axes at once and its keys as well as public sources know them.
- A wrong `published` key mapping shows up as a wrongly named key, not as a missing device; the probe (ADR-0006) is how
  it gets corrected and the entry becomes `checked`.
- The catalog grows with entries nobody here has seen work; the README lists them as such.
- The wire's button set changes width: protocol version 2.

## Rules

- A model whose entry is not `checked` is never described as supported without that qualification.
- Model knowledge, including the descriptor parser and the shared numbering, only in `SpaceMouseKit`.
- Nothing is written to a device to find out what it is; feature reports are only read (GET).

## Enforced and verified by

- `SpaceMouseModel.recognise`, `HIDReportDescriptor` and their tests (the Compact's descriptor as read from the
  IORegistry, 2026-10-15).
- `Devices` matches by usage pair; `SpaceMouseValuesTests`.
- A model nobody here owns, at its owner's device: the SpaceTraveler (046D:C623), not in the catalog, was recognised
  as `guessed` from its descriptor (axes, LED, eight buttons) and reported with Space Probe (issue #1, 2026-10-16).
- Open: a model from the published list at a device.
