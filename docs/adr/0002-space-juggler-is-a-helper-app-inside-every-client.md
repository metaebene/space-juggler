# ADR-0002: Space Juggler is a helper app inside every client, started through Launch Services, with a menu bar item

- Status: accepted (Tim, 2026-10-14); "Quit" in the menu still open; the menu bar item is off by default (ADR-0011)
- Date: 2026-10-14
- Related: ADR-0001

## Context

- The user should install nothing extra and not care which program runs (Tim, 2026-10-14).
- A menu bar item helps debugging (who holds the SpaceMouse) and shows that a SpaceMouse is there as a general input
  device (Tim, 2026-10-14). A menu bar item needs an `NSApplication`; `LSBackgroundOnly` forbids any UI,
  `LSUIElement` allows windows and an `NSStatusItem` without a Dock icon.
- macOS attributes privacy permissions (TCC) to the *responsible* process. A process spawned by an app
  (`posix_spawn`, `Process`) inherits the app's responsibility; a process opened through Launch Services
  (`NSWorkspace.openApplication`) is responsible for itself. The spike ran from a terminal and so proves nothing here.
- Whether seizing a SpaceMouse (usage 0x01/0x08, not a keyboard) needs Input Monitoring is not known.
- None of the four clients is sandboxed.

## Decision

- Space Juggler is an app bundle `Space Juggler.app`, bundle ID `me.metaebene.SpaceJuggler`, `LSUIElement`, hardened
  runtime, signed by the client's team; its one entitlement, `disable-library-validation`, lets it load 3Dconnexion's
  client framework (ADR-0004). Every client embeds it (`Contents/Helpers/`); Space Shuttle's
  installer puts it next to the extension.
- A client starts it through Launch Services (`NSWorkspace.openApplication`, not activating, with
  `createsNewApplicationInstance`, because an older copy with the same bundle ID may be running and must be taken over),
  never as a child process, so it has one identity of its own whichever client starts it.
- It runs while a client is connected and leaves a while after the last one is gone (spike: 10 s).
- Its menu bar item shows the SpaceMouse symbol; the menu lists the devices (on/off, connection, battery, ADR-0003), who
  holds and who waits, the driver state (ADR-0004), and with ⌥ diagnostics. The item can be hidden; since ADR-0011
  it is shown only when a developer turns it on.
- The name stands alone, without explanatory additions (Tim, 2026-10-14).

## Consequences

- Four copies of the same bundle ID exist on disk; Launch Services is always given a URL, never asked by bundle ID.
- If a permission is needed, it is asked once for Space Juggler (to be verified: one grant for all copies, since TCC
  checks bundle ID and the team's designated requirement).
- A sandboxed client could not reach the socket or start the helper; it would need an app group container. Not needed
  today.

## Rules

- Space Juggler is started only through Launch Services, never spawned by a client.
- It reads devices and draws its menu; it never posts events (scrolling, gestures stay in Space Glider).
- One bundle ID for every copy; every copy is signed by the same team.

## Enforced and verified by

- `SpaceJugglerConnection.Launcher.app`, `Scripts/build-space-juggler.sh`, `App/Info.plist`.
- Measured 2026-10-14 (docs/spike.md, run 3): started through Launch Services, `IOHIDCheckAccess(ListenEvent)` "not
  determined", yet both SpaceMice seized: **no permission is needed** to seize a SpaceMouse, so the attribution question
  does not arise. A second copy started while one runs finds it and leaves.
- Open: the menu bar item seen by Tim; name and icon in Activity Monitor and System Settings > Menu Bar.
- Open decision: what "Quit" in the menu means (clients would start it again at once): pause (release all devices,
  keep running) or remembered until a client app starts anew. Until then the menu has no "Quit".
