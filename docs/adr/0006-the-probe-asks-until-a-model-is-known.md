# ADR-0006: Space Probe asks at the device until a model is known

- Status: proposed (2026-10-15); the app is called Space Probe since 2026-10-16 (before: SpaceMouse Probe, a working title)
- Date: 2026-10-15
- Related: ADR-0001 (only Space Juggler opens a SpaceMouse), ADR-0003 (device data to all), ADR-0005 (unknown models);
  `docs/models.md` ("Open at the device")

## Context

- Most SpaceMouse models are known here only from public sources (`docs/models.md`), some not at all. What decides
  whether a model works — which bit is which printed key, the axis range and signs, the LED, what report 0x08 holds —
  can only be seen at a device, and the devices are with other people.
- Reverse engineering 3Dconnexion's driver is out (ADR-0001: observed behaviour only); it would also not say which bit a
  user's key sets on their device.
- Only Space Juggler opens a SpaceMouse (ADR-0001). It decodes reports into what the catalog knows and drops the rest.

## Decision

- **Space Probe** is a small SwiftUI app for anyone with a SpaceMouse. It is a client of Space Juggler like the
  others (embedded `Space Juggler.app`, a claim for its own app), so it never opens a device itself and works beside the
  other clients: while it is in front, it holds the SpaceMouse.
- **Two additions to the protocol** (version 2):
  - `describe(device:)` → `description(DeviceDescription)`: the IORegistry properties, the raw report descriptor and
    every declared feature report, read with GET (over the control pipe when the device is held by someone else). Any
    client may ask (device data, ADR-0003).
  - A claim with `raw: true` gets every input report as it came (`report(device:bytes:)`), as the holder only (input,
    ADR-0001).
- **The probe shows every attached device at once** and leads through a test step by step (Tim, 2026-10-16): the test
  is started explicitly, every step has a page of its own, and the user moves on explicitly once the step is done;
  keys count only in the keys step, the cap only in the cap step. English and German. The steps:
  1. Description (automatic).
  2. Keys: press each key; for every new one the probe asks for the label printed on it (empty: nothing printed; no
     suggestion for the unprinted side buttons or a guessed model). Done when every button the
     descriptor declares has been seen, or the user says there are no more.
  3. Axes: the twelve directions one after another; each records which axis moved, its sign and its peak.
  4. LED: switched on and off on request; the user says whether it lit.
  5. Label: the serial number and name printed on the device, if any (the report says this becomes public).
  6. Check: everything once more, each part changeable, notes added; then the report is created.
  Battery reports are recorded as they come (wireless models).
- **The result is one JSON file** (`format: 1`), put down in `~/Library/Application Support/Space Probe/Reports`,
  exported from there or posted: the report goes to the clipboard and a new issue opens with the device report form
  (`.github/ISSUE_TEMPLATE/device-report.yml`, on the default branch) on metaebene/space-juggler, where the user pastes
  it. GitHub refuses links as long as a report (tried 2026-10-16). Findings from it go into `docs/models.md` and the
  catalog as observed behaviour; an entry becomes `checked`.
- While 3Dconnexion's helper holds the devices (ADR-0004) there are no raw reports: the probe still takes the
  description and asks the user to quit the helper for the rest; it never quits it.

## Consequences

- Every user can turn an unknown or published model into a checked one in a few minutes, without a developer tool.
- The probe exercises the real path: what it sees is what Space Juggler sees.
- A device report contains the device's serial number (report 0x08) when it has one.
- Protocol 2: older brokers do not know the new messages; the probe brings a newer Space Juggler, which takes over.

## Rules

- The probe never opens a device; it asks Space Juggler.
- The only write to a device is the LED, on the user's request.
- Nothing leaves the Mac without the user sending it.

## Enforced and verified by

- `Broker` (`describe`, raw reports only to a raw holder), `WireTests`.
- `Sources/SpaceProbe`, `ProbeSessionTests`; `Scripts/build-space-probe.sh`; `Scripts/release-space-probe.sh`
  (universal, Developer ID, notarized disk image, as Space Glider's ADR-0016).
- Release 0.4.0 (2026-10-16): notarization accepted (submission f9c6e492-9ef2-406c-b360-206e1ed76328), stapled; `spctl`
  accepts the image, the app and Space Juggler.app inside as "Notarized Developer ID"; 2.5 MB, SHA-256
  `51609a3a466caaed53d125e7f2fa3c8cccdef5aa9ac5c8a5e563826195ac1153`.
- At the device (Tim, 2026-10-16): the steps at the SpaceMouse Compact; the report link was too long for GitHub.
- Open: a report from a device nobody here owns.
