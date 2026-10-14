# Spike: broker election, handover and seizing (ADR-0001)

`smk-spike` is broker and client in one command-line tool. `SMK_HOME` moves lock, socket and logs out of
`~/Library/Application Support/Space Juggler`.

```
swift build
SPIKE="$(swift build --show-bin-path)/smk-spike"
$SPIKE client --name NAME [--app BUNDLE-ID]... [--background] [--version N] [--seconds S] [--quiet]
$SPIKE broker [--version N] [--linger S] [--no-devices]     # normally started by a client
$SPIKE status
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
