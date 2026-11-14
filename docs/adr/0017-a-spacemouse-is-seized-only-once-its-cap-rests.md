# ADR-0017: A SpaceMouse is seized only once macOS has seen its cap at rest

- Status: accepted
- Date: 2026-11-14
- Amends: ADR-0001 (its "Seizing": the broker opens a SpaceMouse while somebody holds it, and seizes it once the cap
  rests)
- Related: ADR-0003 (input of a device that is off), ADR-0004 (the driver's way, unchanged), ADR-0010 (`CapRest`)

## Context

- Without 3Dconnexion's driver, macOS itself claims a SpaceMouse nobody has seized: its HID event driver
  (`AppleUserHIDEventDriver`, property `MultiAxisPointer` on the device) turns it into a pointer. Tilting the cap moves
  the mouse pointer, twisting it scrolls, and a timer repeats the last deflection it saw until a report of all zeros
  comes or the device goes away.
- Space Juggler opened the device seized (`kIOHIDOptionsTypeSeizeDevice`) at once. A seized device's reports reach
  nobody else: seized while the cap was deflected, macOS never saw it come back, and the pointer kept wandering until
  the SpaceMouse was unplugged, or released and tapped.
- Reproduced on Tim's Mac (2026-11-14, no 3Dconnexion driver): cap held tilted, Kugelblitz started (Space Juggler
  seized), cap let go: the pointer kept moving up. Kugelblitz quit (released) and the cap tapped: it stopped. A user's
  report (SpaceNavigator 046D:C626, Kugelblitz's "keep in background" on) showed `rx -60, y -60` as the first report
  after seizing: a hand on the cap at the moment of the seize.
- A cap in its middle reports all zeros once and then nothing; a deflected one reports about every 16 ms, even while the
  deflection stays the same (ADR-0010). A worn cap may never report zeros; `CapRest` takes its rest after 1.5 s of
  stillness near the centre (ADR-0010).

## Decision

- **Opened first, seized later.** When a device is wanted (a holder appears, comes back to the front, the device is
  plugged in again, a retry after "busy"), Space Juggler opens it **without seizing** and passes its input to the
  holder at once, through the same `Reports` as before (buttons, axes from the cap's rest, raw reports). Its state is
  "open" from then on, as before.
- **`SeizeGate`** (pure, one per open device while unseized) decides when to seize, from the raw reports:
  - **quiet**: the last axis picture since the open was all zeros, or none came at all, no button is held, and no axis
    or button report came for **0.25 s** (`SeizeGate.quiet`, about fifteen report intervals of a deflected cap: a late
    report over Bluetooth does not look like a rest, and macOS has taken the zeros before it hears nothing more);
  - **rested** (the worn-cap fallback): the raw axes have stayed where `CapRest` takes a rest, within `wobble`
    (4 units) for `settle` (1.5 s) and within `reach` (a sixth of the full scale), and no button is held.
- A held cap is neither: it is not seized until the hand lets go. There is no bare deadline: a timer alone would seize
  a cap held tilted for longer than it, which is exactly the reproduced case.
- **Seizing** closes the unseized device object and opens the device again with `kIOHIDOptionsTypeSeizeDevice`, with a
  new report buffer and the **same `Reports`**: buttons are reported on change only, the cap's rest and the half of an
  axis pair carry over, so nothing is repeated to the holder. A report that finds the gate open has the seize wait for
  the next turn of the main queue (not inside the device object's own callback), which asks the gate again; a quiet cap
  sends no report and is looked at by a timer at the moment it becomes quiet (`SeizeGate.nextCheck`; while a button
  is held or the cap is off zero, every 0.25 s). A seize that fails goes back through the open and its gate, like any
  failed open ("busy": tried again for 2 s).
- The broker logs "opened … seizing once the cap rests" and "seized … N s after opening: cap at rest | cap resting off
  its centre".
- The LED write of a device nobody holds (`setLED`, ADR-0003) still opens its own device object seized for the few
  milliseconds of the write and closes it again, as before; while a device is open, unseized or seized, the write goes
  through that object.
- `SpaceJuggler.version` goes to 18; the protocol stays 2.

## Consequences

- macOS always sees the cap return to zero before Space Juggler takes the device: a cap held while an app takes the
  SpaceMouse no longer leaves the pointer wandering.
- Until the cap rests, macOS gets the reports too: a hand already on the cap when the app takes the SpaceMouse moves
  the pointer (or scrolls) as well as the app, until it lets go; buttons pressed in that time may reach macOS as well.
  An untouched cap is seized 0.25 s after the open; a worn one 1.5 s after it.
- Remaining risk, worn cap: a cap resting off its centre is seized while macOS still sees its last small deflection,
  as before this ADR (macOS may repeat it). A worn cap that never stays within 4 units is never seized: macOS moves
  the pointer by it as it does without Space Juggler, and the app gets its input unseized.
- Remaining risk, a hand: a hand holding the cap within a sixth of its scale and within 4 units for 1.5 s counts as
  rested (as in ADR-0010); a touch in the microseconds between closing the unseized object and the seize reaches
  macOS only. Either leaves macOS with a deflection, rarely.
- An unseized open may need what a seized one does not (Input Monitoring for listening): not seen for the serial number
  and feature reports, which open their device objects unseized (ADR-0003, ADR-0006), but those never listened to
  input reports; to be checked at the device.

## Rules

- Space Juggler seizes a SpaceMouse only through `Devices.seize`, only once `SeizeGate` says the cap rests for macOS;
  every open goes through `Devices.open` without seizing first.
- `SeizeGate` decides only from raw reports (what macOS saw), never from the deflection passed to the holder.
- No bare deadline seizes a cap: only quiet after zeros (or nothing) or a rest as `CapRest` takes it, never while a
  button is held.
- One `Reports` per device from the open until it is let go, across the reopen that seizes it.

## Enforced and verified by

- `SeizeGate`, `Reports.awaitRest`/`seizable`/`seized`/`untilNextCheck`, `Devices.open`, `Devices.seize`,
  `Devices.watchForRest`, `Devices.failed`.
- `SeizeGateTests`: an untouched cap seized after 0.25 s; a cap held at `rx -60, y -60` for 5 s and a hand wobbling
  near the centre for 5 s never, then 0.25 s after the zeros; a cap passing through zero not; a worn cap after 1.5 s;
  a held button waits for its release, also for a worn cap.
- `ReportsTests`: opened while tilted, the holder steers at once, seizable only 0.25 s after the zeros (found by a look,
  not a report), the watch over once seized, the buttons going on after it; a worn cap found from its own reports at
  1.5 s, and no longer seizable once a hand comes before the seize; nothing seizable unless watching.
- 2026-11-14 at the device (Tim's Mac, SpaceMouse Compact over USB, 3Dconnexion's helper not running, macOS's
  `AppleUserHIDEventDriver` with `MultiAxisPointer` on the device, so tilting moved the pointer): before, with version
  17, the cap held tilted while Kugelblitz took the SpaceMouse and then let go – the pointer kept moving up until
  Kugelblitz was quit and the cap tapped. With version 18 (Kugelblitz built against this branch): the cap held tilted,
  ⌘-Tab to Kugelblitz – the globe steered at once, the pointer moved along while held; let go – the pointer stopped,
  log "seized … 2.66 s after opening: cap at rest"; afterwards tilting moved only the globe. An untouched cap: "seized
  … 0.26 s after opening: cap at rest". No Input Monitoring prompt appeared.
- Open, at the device: an old SpaceNavigator resting off its centre seized about 1.5 s after the open ("cap resting
  off its centre"); a button held while an app takes the SpaceMouse.
