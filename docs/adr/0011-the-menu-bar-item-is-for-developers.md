# ADR-0011: Space Juggler's menu bar item is for developers and off by default

- Status: accepted (Tim, 2026-10-27)
- Date: 2026-10-27
- Related: ADR-0002 (the helper app and its menu bar item, amended here); ADR-0008 (the menu bar symbol)

## Context

- ADR-0002 gave Space Juggler a menu bar item: who holds the SpaceMouse, the devices, the driver state, the log.
- That is what a developer needs while working on a client. A user of Stagehand, Kugelblitz, Space Glider or Space
  Shuttle installed one app and should not see a second item appear in the menu bar for a helper they never chose
  (Tim, 2026-10-27).

## Decision

- Space Juggler shows its menu bar item only when the user default `showsMenuBarItem` of its bundle ID is on:

  ```
  defaults write me.metaebene.SpaceJuggler showsMenuBarItem -bool YES
  defaults write me.metaebene.SpaceJuggler showsMenuBarItem -bool NO
  ```

- One bundle ID for every copy (ADR-0002), so the one setting holds whichever client starts Space Juggler.
- A running Space Juggler follows the setting at once (key-value observation of `UserDefaults`, which sees changes from
  other processes); it logs when the item appears or goes.
- Without the item Space Juggler works as before; only the view is missing.

## Consequences

- Users see nothing of Space Juggler but its name in Activity Monitor.
- Turning a device off (ADR-0003) needs the menu, so for now only a developer can; a client that wants to offer it to
  users needs its own way, through the broker.
- `space-juggler-cli` status and `Show Log` stay the ways to look inside.

## Rules

- The menu bar item appears only while `showsMenuBarItem` is on.

## Enforced and verified by

- `AppDelegate.followMenuBarSetting`, `AppDelegate.updateStatusItem`.
- Checked 2026-10-27: key-value observation of a `UserDefaults` key sees `defaults write` and `defaults delete` from
  another process. Open: the item appearing and going in Space Juggler.app itself.
