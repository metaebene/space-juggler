# ADR-0003: Several SpaceMice are told apart by a fixed identity, each can be turned off, the others act as one

- Status: accepted (Tim, 2026-10-14); built in the spike for identity only
- Date: 2026-10-14
- Related: ADR-0001, ADR-0002; Kugelblitz ADR-0165 (several devices); stagehand ADR-0092 (serial number)

## Context

- More than one SpaceMouse can be attached (Tim, 2026-10-14). Kugelblitz already joins several into one input
  (`SpaceMouseFleet`, its ADR-0165): buttons held on any device count, axes come from whichever moves.
- Only the SpaceMouse Wireless reports a serial number (vendor feature report 0x08, GET only, stagehand ADR-0092; the
  same on Bluetooth and on its cable). The Compact, the SpaceNavigator and the SpaceMouse Pro have none.
- Settings must refer to a device by a fixed identity, never by name or enumeration order (Tim's rule in all his apps).
- The LED and the battery are not input: other clients than the holder need them (Stagehand's LED step and battery
  warnings run in the background).

## Decision

- **Identity**, in this order: `serial:<S/N>`; else `bt:<address>` over Bluetooth; else `port:<vid>:<pid>@<LocationID>`.
  A device without a serial number that moves to another port counts as another device.
- **On/off** per device in Space Juggler's menu, stored by identity. "Off" means: Space Juggler leaves the device alone
  or holds it and drops its input; which one depends on whether a released SpaceMouse scrolls (docs/spike.md, run 2).
- **All devices that are on go to the same holder and act as one**, like Kugelblitz's fleet. Events name their device,
  because the models' buttons differ.
- **Later, if wanted:** assignment per device (a claim with a device filter; the arbitration of ADR-0001 then per
  device).
- **Information to every client:** the device list (identity, model, transport, serial number, battery, on/off,
  open state) is sent to all clients, holder or not. **The LED** can be set by any client; Space Juggler writes it,
  mirrors the state (the device does not report it) and tells all clients.

## Consequences

- Kugelblitz's fleet logic moves into Space Juggler.
- Two identical SpaceMice without serial numbers keep their settings only as long as they stay on their ports.
- Stagehand keeps its LED step and battery warnings while another program has the input.

## Rules

- Devices are referred to only by their identity.
- Input of a device that is off never reaches a client.
- Device information and LED are not input: they go to all clients.

## Enforced and verified by

- Spike: identity `port:046d:c626@02110000` for the SpaceNavigator (2026-10-14).
- Open: two devices at once, the Wireless's serial on both transports, on/off in the menu, the LED written for a client.
- Open: report 0x08 as an identity for the Compact (filled, another format) and the SpaceNavigator (empty);
  `docs/serial-report.md`.
