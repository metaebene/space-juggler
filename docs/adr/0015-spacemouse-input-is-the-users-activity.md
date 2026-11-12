# ADR-0015: SpaceMouse input is told to macOS as the user's activity

- Status: superseded in part by ADR-0016 (a declaration alone did not keep the screen saver off)
- Date: 2026-11-12
- Related: ADR-0001 (Space Juggler seizes every SpaceMouse), ADR-0002 (it reads, it never posts events), ADR-0004
  (the driver's input), ADR-0010 (the deflection from the cap's rest); Kugelblitz report f25fb962

## Context

- A Kugelblitz user steering only with a SpaceNavigator saw the screen saver start after a while: the Mac took them
  for idle (report f25fb962, 2026-11-12).
- Input of a HID device opened with `kIOHIDOptionsTypeSeizeDevice` reaches only the process that seized it. A mouse or
  keyboard tickles the system's idle timer on its way through the HID event system (in `pmset -g assertions` a
  short `UserIsActive` assertion of WindowServer, "iohideventsystem.queue.tickle"); a seized SpaceMouse does not. So
  screen saver, display sleep and the lock that follows them count a Mac steered with a SpaceMouse as idle.
- `IOPMAssertionDeclareUserActivity(…, kIOPMUserActiveLocal, …)` is the public way to say the same: it raises the
  same `UserIsActive` state in powerd (`pmset -g useractivity`: "User is active on the system"), turns the display on
  and postpones display sleep within the user's settings. It needs no entitlement, works in any process and posts no
  event; the assertion lets go by itself. (`IOHIDSystem`'s `HIDIdleTime` does not move under it: that counter is the
  HID system's own.)
- A client cannot do this for everyone: each would have to, and an app in the background does not know whether
  anyone else gets the input. Space Juggler takes the device away from the system, so it gives the activity back.

## Decision

- The broker declares the user's activity for input of a seized SpaceMouse and for input that comes through
  3Dconnexion's driver while Space Juggler is its client: axes while the deflection is not zero (a zero deflection is
  the cap let go, ADR-0010, so a cap at rest keeps nobody awake), buttons on every change.
- At most once every 10 seconds (`UserActivityPacing.interval`; the shortest idle time macOS offers is one minute),
  always with the same assertion ID, which the system takes as more activity of the same kind.
- Whether anyone holds the device does not matter: someone moved it. Input of a device turned off in the menu reaches
  nobody and counts for nothing (ADR-0003). A failed declaration is logged once per run of failures.
- `SpaceJuggler.version` goes to 16, so that apps updating take over from older copies; the protocol stays 2.

## Consequences

- A Mac steered only with a SpaceMouse behaves as one steered with a mouse: no screen saver, no display sleep, no
  lock while it moves; once it stops, the user's idle times run as usual. A moved SpaceMouse wakes a display that has
  gone to sleep, as a mouse does.
- Every client gets this with the broker of version 16, without a change of its own.
- A cap that drifts off its centre without resting there (a worn device) would count as activity until `CapRest`
  takes its new rest after 1.5 s; after that it is zero again.

## Rules

- Space Juggler tells macOS of a SpaceMouse's input only through `UserActivity`, as a declaration of user activity
  (`IOPMAssertionDeclareUserActivity`), never as an event; clients do not do it themselves.
- Only real input counts: axes off zero, button changes; nothing the broker sends by itself (a device turned off).

## Enforced and verified by

- `UserActivityPacing`, `UserActivity`; `Broker` calls it from `Devices.onAxes`/`onButtons` and from the driver's.
- `UserActivityTests`: a moving cap declared at 0, 10, 20 and 30 s of 30 s of reports, a cap let go never, buttons
  sharing the interval, the same assertion ID again, a failure logged once.
- Checked on macOS 27.2: a declaration shows as "User is active on the system" in `pmset -g useractivity`.
- Open: at the device, a Mac with a one-minute screen saver steered only with a SpaceMouse for several minutes, with
  Space Juggler's own seizing and through 3Dconnexion's driver.
