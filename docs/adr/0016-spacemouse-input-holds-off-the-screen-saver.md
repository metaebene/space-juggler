# ADR-0016: SpaceMouse input holds off the screen saver with a display assertion

- Status: proposed
- Date: 2026-11-12
- Supersedes: ADR-0015 in part (its declaration of user activity stays; its rule that this is all Space Juggler tells
  macOS goes)
- Related: ADR-0001, ADR-0002, ADR-0004, ADR-0010; Kugelblitz report f25fb962

## Context

- With version 16 (ADR-0015) Space Juggler declared the user's activity while a SpaceMouse moved. Tim steered
  Kugelblitz with a SpaceMouse Compact through 3Dconnexion's driver for a minute with a screen saver of one minute,
  and the screen saver started anyway (2026-11-12, 15:18:39).
- loginwindow's log says why. Its `ScreenSaverDaemon` compares an `actualUserIdle` with the idle time of the setting
  ("actualUserIdle = 60.0, targetUserIdle = 60.0 … starting screen saver due to user idle"). That idle time is the HID
  system's (`IOHIDSystem`'s `HIDIdleTime`), which a declaration of user activity does not reset (measured: unchanged
  across `IOPMAssertionDeclareUserActivity`). powerd took the declaration ("Created UserIsActive \"SpaceMouse input\""),
  but the screen saver does not ask powerd whether the user is active.
- What it does ask is whether display sleep is blocked: "PMDisplaySleepIsBlocked … IS blocked … PMNoDisplaySleepEnabled
  so do not launch screen saver … scheduling idle timer in <idle time>s" (seen on 2026-11-09 with another app's
  assertion). A `PreventUserIdleDisplaySleep` assertion is what video players hold; it needs no entitlement.
- Resetting the HID idle time itself would mean posting events (`CGEventPost`, `IOHIDPostEvent`): it needs the
  Accessibility permission, and Space Juggler never posts events (ADR-0002).
- While blocked, loginwindow looks again only after a whole idle time. Once the assertion goes, the screen saver
  starts at that next look, if the HID system has been idle long enough, so anywhere up to one idle time after the
  release.

## Decision

- On SpaceMouse input (as in ADR-0015: axes off zero, button changes, from Space Juggler's own devices and through
  3Dconnexion's driver, at most every 10 s) Space Juggler declares the user's activity as before (it wakes the
  display and resets powerd's idle time) **and** takes a `PreventUserIdleDisplaySleep` assertion ("SpaceMouse
  input"), unless it holds one.
- It lets the assertion go once no input came for the **hold**: the user's screen saver idle time (`idleTime` of
  `com.apple.screensaver` for the current host, read at every declaration; 0 is "never"), at least one minute and at
  most ten minutes (`UserActivityPacing.hold`); without a setting, ten minutes. So the screen saver starts no sooner
  after the last input than after a mouse's, up to idle times of ten minutes; the cap keeps the display from staying
  on for hours where a user set a long idle time but a short display sleep.
- One pending check at a time: it waits until the last declaration is a hold old, then releases.
- `SpaceJuggler.version` goes to 17; the protocol stays 2.

## Consequences

- While someone steers with a SpaceMouse, neither the screen saver nor display sleep starts. After the last input the
  screen saver comes between one hold and one hold plus one idle time later; display sleep no sooner than one hold
  later.
- `pmset -g assertions` names Space Juggler with "SpaceMouse input" while it holds the display, as it names a video
  player.
- With an idle time over ten minutes the screen saver may come sooner after the last SpaceMouse input than after a
  mouse's (from ten minutes on). With a display sleep shorter than the hold the display stays on up to the hold.

## Rules

- Space Juggler tells macOS of SpaceMouse input only through `UserActivity`: a declaration of user activity and a
  `PreventUserIdleDisplaySleep` assertion released after the hold; never an event. Clients do not do it themselves.
- Only real input counts: axes off zero, button changes; nothing the broker sends by itself.
- The hold comes only from `UserActivityPacing.hold`.

## Enforced and verified by

- `UserActivity` (with `Power` for what it asks of the system), `UserActivityPacing`; `Broker` calls it from
  `Devices.onAxes`/`onButtons` and from the driver's.
- `UserActivityTests`: pacing as before; the hold from the idle time (60, 300, 7200 → 600, never → 60, none → 600);
  the display held once over 50 s of steering, released a hold after the last declaration and taken again on new
  input; a failure logged once per run.
- Checked at the device (Tim, 2026-11-12): a SpaceMouse Compact through 3Dconnexion's driver, screen saver after one
  minute; while steering it stayed off ("PMNoDisplaySleepEnabled so do not launch screen saver"), the assertion went
  60 s after the last declaration and the screen saver started at loginwindow's next look, about 90 s after the
  last input.
- Open: the same with Space Juggler's own seizing (no 3Dconnexion driver).
