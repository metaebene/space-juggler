# ADR-0013: A driver that passes nothing on is told to every client, with why

- Status: proposed
- Date: 2026-11-07
- Related: ADR-0004 (driver mode), ADR-0012 (registration tried again); Kugelblitz ADR-0226 (a failure is shown only
  with a SpaceMouse attached)

## Context

- On Tim's Mac on 2026-11-07 (macOS 27.2, 3DxWare 10.8.13, helper 1.4.4, driver extension 1.4.623) the driver
  extension could not be switched on in System Settings (`systemextensionsctl`: "terminating for disable but still
  running"). The helper launched at the login (00:46:23) and never finished launching: its main thread sat in its
  nib's awake code, in a run loop of its own asking Launch Services for running apps (`sample`); Activity Monitor
  called it "not responding". It had the SpaceMouse open exclusively all the same (its `IOHIDLibUserClient`; a seize
  and a shared open both got `kIOReturnExclusiveAccess`), and the virtual "3Dconnexion Virtual Data" device (256F:C672)
  that carries the client API was missing, so every `SetConnexionHandlers` returned -36.
- Space Juggler went to driver mode because the helper was listed (ADR-0004), failed every registration, and told the
  clients nothing: the devices said "driver", Kugelblitz said "connected", the SpaceMouse did nothing.
- `NSRunningApplication.isFinishedLaunching` said `false` for the helper 70 min after its launch; every launch of the
  helper in the broker logs since 2026-10-14 was followed by a registration within seconds. It is public, needs no
  permission and costs a look at the list the broker already reads.

## Decision

- **`DriverHealth`** (pure) decides, while the helper runs, why the driver passes nothing on:
  - `helperNotResponding`: the helper has not finished launching 30 s after its launch (`launchDate`, else when the
    broker first saw it);
  - `driverNotAnswering`: it has, but the registration failed three times in a row (about 7 s; the first try after a
    login often fails once, ADR-0012);
  - otherwise none.
- **Every device the driver holds carries it** (`SpaceMouseDevice.driverProblem`: a `code` and an English `detail`),
  sent with the device list, so every client hears of it as it begins, changes and ends, holder or not. The field is
  optional: older clients ignore it, clients reading an older broker get nil, a code a client does not know it shows by
  `detail`. The protocol stays 2.
- The broker asks `DriverHealth` whenever driver mode or the registration changes, and every 5 s while the helper runs
  (whether it finished launching is not observed). A problem is logged when it begins or changes and when it ends.
- Nothing else changes: Space Juggler still goes through the driver while the helper is listed, keeps trying to
  register (ADR-0012), and never quits the helper. Taking the device over from a hanging helper is a decision of its
  own.

## Consequences

- An app can say what is wrong ("3Dconnexion's driver is not responding") instead of "connected", and a problem report
  carries the cause.
- A helper that hangs after it finished launching is not seen; the failing registrations then show it as
  `driverNotAnswering` only if it was never registered in this run of driver mode.

## Rules

- Why the driver passes nothing on is decided only by `DriverHealth` and told only as `SpaceMouseDevice.driverProblem`
  of the devices in state "driver".
- A client names a problem by its `code`, never by its `detail`.

## Enforced and verified by

- `Sources/SpaceJugglerCore/DriverHealth.swift`; `Broker.updateDriverProblem`, `scheduleHealthCheck`;
  `Devices.driverProblem`; `DriverClient.onChange`.
- `Tests/SpaceJugglerTests/DriverHealthTests.swift`: no helper, the grace, the hanging helper first, failures from the
  third, the same detail while the problem lasts, the optional field on the wire.
- Open at the device: a hanging helper shown as `helperNotResponding` (the helper of 2026-11-07 was force-quit before
  the broker could be tried on it; seen only when it hangs again).
