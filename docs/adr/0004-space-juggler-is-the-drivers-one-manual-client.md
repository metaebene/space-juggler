# ADR-0004: While 3Dconnexion's helper runs, Space Juggler is the driver's one manual client

- Status: accepted (Tim, 2026-10-14); checked at the device with all four apps (run 6)
- Date: 2026-10-14
- Related: ADR-0001; `docs/3dxware-package.md`; stagehand `docs/spacemouse-findings.md` ("Routing")

## Context

- 3DxWare 10.8.13 (`docs/3dxware-package.md`) is one driver with two states: its user-space helper
  (`com.3dconnexion.driver.helper`, started at every login) either runs and holds every SpaceMouse exclusively, or
  does not run. The driver extension only publishes virtual devices.
- The driver's client API routes data to the frontmost app's client (`'****'`); a background client gets data only as
  a *manual* client (`'++++'`) after `'3dac'`, which starves every other client until `'3ddc'` (stagehand findings).
- Every program must be able to use the SpaceMouse in front, also indirectly through Space Glider, which is never in
  front; background use may be impossible in some cases (Tim, 2026-10-14).
- Helper 1.4.2 crashed (`insertObject: nil`) after manual registrations from app bundles. Measured 2026-10-14 with
  helper 1.4.4: a manual registration **without a client name** from Space Juggler.app crashed it at once and left the
  driver without helper; **with a name** it registers, activates, deactivates and unregisters, and the helper keeps
  running (`docs/spike.md`, run 5). The command-line probe always passed a name.

## Decision

- While the helper runs (seen through `NSWorkspace`, launch and termination followed), Space Juggler does not seize
  and goes through the driver instead: it registers once as a manual client (`'++++'`, takeover, all axes and
  buttons) **with its name**, a second after it found the helper.
- It activates the client (`'3dac'`) while one of its clients holds the SpaceMouse and deactivates it (`'3ddc'`)
  otherwise, so the frontmost app's own driver client (Blender, Google Earth …) gets the data back.
- Through the driver only claims for the frontmost app count; background claims are not served there, because Space
  Juggler would take the data from every app in front, including those with their own support.
- The driver merges every SpaceMouse and does not say which one moved: its input is put down to the first device that
  is on, and its buttons are named by that device's model. Devices are reported with the state `driver`.
- LED requests go to the driver (`'3dsl'`; the Compact ignores it).
- When the helper goes away, Space Juggler unregisters and seizes again. It never starts, stops or kills the helper.
- Space Juggler.app carries `com.apple.security.cs.disable-library-validation` to load the vendor's framework.

## Consequences

- Clients do not change: the same claims, the same events, whether the driver is there or not.
- With the helper running, Kugelblitz's "keep in background" and Stagehand's background triggers get nothing.
- With several SpaceMice and the driver, buttons are named after the first device's model.
- The driver pre-scales axis values by its own speed setting (seen up to ±522 instead of ±350).

## Rules

- Register with the driver only with a client name.
- Only Space Juggler registers with the driver; clients never do.
- Never start, stop or kill the 3Dconnexion helper.
- Through the driver, only front claims are served.

## Enforced and verified by

- `DriverClient` (name, activation), `Broker.updateDriverMode`, `Broker.arbitrate` (background claims dropped in driver
  mode), `Devices.driverHolds`; `App/SpaceJuggler.entitlements`.
- Run 5 (2026-10-14): crash without a name, then with the name registered as client 4096/4097, activated for a front
  claim, deactivated and unregistered; helper alive afterwards.
- At the device (Tim, 2026-10-14, run 6): input through the driver in each of the four apps; 3Dconnexion's own apps
  in front get the SpaceMouse back.
