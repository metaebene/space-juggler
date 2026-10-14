# Spike and test runs: election, handover, seizing, the app (ADR-0001, ADR-0002)

`space-juggler-cli` (was `smk-spike`) runs test clients and a broker without UI. `SPACE_JUGGLER_HOME` moves lock,
socket and logs out of
`~/Library/Application Support/Space Juggler`.

```
swift build
SPIKE="$(swift build --show-bin-path)/space-juggler-cli"
$SPIKE client --name NAME [--app BUNDLE-ID]... [--background] [--version N] [--seconds S] [--quiet] [--launch-app PATH]
$SPIKE broker [--version N] [--linger S] [--no-devices]     # normally started by a client
$SPIKE status
$SPIKE led DEVICE-ID on|off
```

## Run 1 — automatic, 2026-10-14 (`Scripts/spike-scenario.sh`)

Mac: macOS 27.2, Apple silicon. Attached: SpaceNavigator (046D:C626, USB, no serial number). No 3DxWare installed,
none of the four apps running. Frontmost app: VS Code.

| Step | Expected | Seen |
|---|---|---|
| Background client starts alone | starts broker v1, holds | yes; broker up and connected in ~200 ms, seize took 3 ms |
| Client claiming the frontmost app | takes over from the background client | yes |
| Client bringing v2 | v1 hands over, clients reconnect | yes; lock taken 25 ms after asking, clients back after ~100 ms, seize at once (no busy retry) |
| `kill -9` of the broker | a client starts the newest (v2), even the one whose own is v1 | yes; ~0.7 s gap (0.5 s waiting before starting); the two other clients' brokers saw v2 running and left |
| Front client quits | background client holds again | yes |
| Last client gone | broker releases the device, leaves after the linger time | yes (10 s) |

Also learned: a Unix socket path must stay under 104 bytes. Application Support is fine
(`/Users/<name>/Library/Application Support/Space Juggler/broker.sock`), a deep scratch directory is not.

## Run 1b — the libraries, two SpaceMice, 2026-10-14

The same scenario on `SpaceJugglerCore`/`SpaceJugglerClient`, with a SpaceNavigator and a SpaceMouse Pro attached
(identities `port:046d:c626@02110000`, `port:046d:c62b@02130000`): both seized and released together, every step as in
run 1. After a handover or restart the broker now waits 0.3 s before deciding, so the input no longer flickers to the
first client that reconnects.

## Run 3 — Space Juggler.app through Launch Services, 2026-10-14

`Scripts/build-space-juggler.sh` (debug, Apple Development), two copies in `HostA.app/Contents/Helpers` and
`HostB.app/Contents/Helpers`; a test client with `--launch-app` pointing at A.

| Check | Seen |
|---|---|
| Client starts the app through Launch Services | yes; first connection after ~1.4 s |
| `IOHIDCheckAccess(ListenEvent)` in the app | "not determined" (never granted to Space Juggler) |
| Seizing both SpaceMice without that permission | succeeded, no dialog in the log's path: **Input Monitoring is not needed** for 0x01/0x08 |
| Second copy (B) started with `open -n` while A runs | started, found A (same version) and left |
| Idle | released the devices when the client quit, left 10 s later |

## Run 4 — all four apps at the device, 2026-10-14 (Tim)

SpaceNavigator and SpaceMouse Pro attached, no 3DxWare, Ultraschall (old Space Shuttle inside) quit; Stagehand
installed (Release), Kugelblitz (Release from its worktree), Space Glider (`make run`), Space Shuttle in the
development REAPER.

- Foreground: Stagehand gets the SpaceMouse once one is on its list (Space Juggler starts, its menu bar item appears);
  Kugelblitz, REAPER with Space Shuttle and an app turned on in Space Glider each get it while in front, Stagehand
  otherwise. Tim: "Funktioniert alles."
- Background: Kugelblitz with "Auch im Hintergrund behalten" keeps it while another app without a claim is in front,
  ahead of Stagehand. Works.

## Run 5 — through 3DxWare 10.8.13, 2026-10-14

Helper 1.4.4 running after a restart, holding both SpaceMice (Space Juggler started by Stagehand at login: `busy`).

| Check | Seen |
|---|---|
| `spacemouse-probe client --signature '++++' --name … --activate` | registered (client 4096), activated; helper alive |
| Space Juggler.app registering `'++++'` without a name | **helper crashed at once**; registration returned no client ID after ~3 s; restarted with `launchctl kickstart gui/<uid>/com.3dconnexion.helper` |
| Same with the name "Space Juggler" | registered (4096/4097), activated for a front claim, deactivated when the client left, unregistered when Space Juggler left; helper alive |

## Run 2 — at the device (needs Tim)

1. **Events.** `$SPIKE client --name A --background`, move the cap, press both buttons: axes (every tenth) and button
   lines appear; macOS does not scroll meanwhile.
2. **Front follows the app.** In two terminals: `$SPIKE client --name Safari --app com.apple.Safari` and
   `$SPIKE client --name Finder --app com.apple.finder`. Switch between Safari and Finder and move the cap: only the
   one in front prints axes; in any other app nobody does and the device is released (`$SPIKE status`).
3. **Released device.** With no client running (`$SPIKE status` says "no broker"): does moving the cap scroll a window
   under the pointer? That decides what "off" in the menu means (ignore vs. leave to macOS).
4. **Two SpaceMice.** Attach a second one: both appear in `status` with different identities, both steer the holder.

## Not yet tried

- A broker as an app bundle (`LSUIElement`) started by a signed app, with its menu bar item; TCC attribution.
- 3DxWare: classic helper (broker cannot seize → clients use `'****'`), DriverKit edition.
- A client inside REAPER.
