# Space Juggler

Several macOS programs want the 3Dconnexion SpaceMouse, but a HID device can only be held by one of them, and
3Dconnexion's own driver wants it too. **Space Juggler** is a small broker that owns every attached SpaceMouse and hands
its input to one program at a time, by simple rules:

1. A program that claims the frontmost app gets it (its own app, the app it lives in, or apps it steers).
2. Otherwise a program that wants it in the background, the one that last had it in front first.
3. Nobody listens in.

Every client app carries Space Juggler inside its bundle and starts it when needed; whichever copy is newest runs, so
updating any one app brings new device support to all of them. Nothing extra to install. With 3Dconnexion's driver
running, Space Juggler becomes the driver's one client and hands the device back to the driver's own apps in front.

The package also contains **SpaceMouseKit**, the model catalog and report decoding, usable on its own, and
**Space Probe**, a small app that finds out what a SpaceMouse model sends (see below).

## Supported devices

Checked at a device:

| Model | Vendor:Product | Buttons |
|---|---|---|
| SpaceMouse Compact | 256F:C635 | 2 |
| SpaceNavigator | 046D:C626 | 2 |
| SpaceMouse Pro | 046D:C62B | 15 |
| SpaceMouse Wireless (Bluetooth and on its cable) | 256F:C63A | 2 |
| SpaceTraveler | 046D:C623 | 8 |

**Not yet checked** — known from public sources only ([docs/models.md](docs/models.md)); they should work, but nobody
here has seen them do so:

| Model | Vendor:Product | Buttons |
|---|---|---|
| SpaceNavigator for Notebooks | 046D:C628 | 2 |
| SpaceExplorer | 046D:C627 | 15 |
| SpacePilot | 046D:C625 | 21 |
| SpacePilot Pro | 046D:C629 | 31 |
| SpaceMouse Wireless (2013, cable / receiver) | 256F:C62E / C62F | 2 |
| SpaceMouse Pro Wireless (cable / receiver / Bluetooth Edition) | 256F:C631 / C632 / C638 | 15 |
| SpaceMouse Enterprise | 256F:C633 | 31 |
| SpaceMouse Wireless and Pro Wireless through the Universal Receiver | 256F:C652 | 2 / 15 |

Any other SpaceMouse (a Multi-axis Controller of Logitech or 3Dconnexion) is taken as well: its axes from what it
declares, its keys guessed.

## Help: run Space Probe

If you have a SpaceMouse that is not in the first table, **Space Probe** asks you to press every key and move the
cap every way, and writes down what the device sends. It opens a GitHub issue with the report (or saves it as a file);
that is how a model becomes checked. **Download:** `SpaceProbe-<version>.dmg` from the
[latest release](https://github.com/metaebene/space-juggler/releases/latest) (signed and notarized, macOS 14 or later;
English and German), or build it with `Scripts/build-space-probe.sh`. It never changes your device except for switching its LED when you ask, and works next to
3Dconnexion's driver (for keys and axes, quit 3Dconnexion's helper while it runs).

## Using it in an app

```swift
// Package.swift
.package(url: "https://github.com/metaebene/space-juggler.git", from: "0.2.0")
// target dependency
.product(name: "SpaceJugglerClient", package: "space-juggler")
```

```swift
import SpaceJugglerClient

let juggler = SpaceJugglerConnection(name: "My App", claim: Claim(apps: [Bundle.main.bundleIdentifier!]))
juggler.onEvent = { event in
    switch event {
    case .axes(let axes, _): print(axes)                       // raw device units, ±350
    case .buttons(_, _): print(juggler.heldButtons)            // all devices together
    case .holding(let holds): print(holds ? "mine" : "someone else's")
    default: break
    }
}
juggler.start()
```

Embed `Space Juggler.app` as `Contents/Helpers/Space Juggler.app`: `Scripts/build-space-juggler.sh [debug|release]
<directory>` builds it (`SIGN_IDENTITY` = your identity; `UNIVERSAL=1`, `TIMESTAMP=1` for distribution; `SCRATCH_PATH` = a build
directory of your own, since SwiftPM's checkout of the package is read-only). The client
starts it through Launch Services when nobody answers.

## Parts

- `SpaceMouseKit` — models (IDs, buttons per model, LED, battery, serial number, how each is known), input reports,
  report descriptors, the device state of 3Dconnexion's classic client API.
- `SpaceMouseKitUI` — a SwiftUI drawing of a SpaceMouse and its cap's twelve directions.
- `SpaceJugglerProtocol` — the messages between Space Juggler and its clients (one JSON object per line over a Unix
  socket in `~/Library/Application Support/Space Juggler`), versioned.
- `SpaceJugglerClient` — what an app links.
- `SpaceJugglerCore`, `SpaceJuggler` — the broker and its menu bar app.
- `space-juggler-cli` — status, test clients (`--raw` prints every input report), `describe` (report descriptor and
  feature reports of a device) and a broker without UI.
- `SpaceProbe` — the probe app (ADR-0006).

Design decisions: [docs/adr](docs/adr/README.md). Test runs: [docs/spike.md](docs/spike.md).

```
swift build
swift test
```

## Licence

MIT, see [LICENSE](LICENSE). SpaceMouse is a trademark of 3Dconnexion; this project is not affiliated with 3Dconnexion
and contains none of its code.
