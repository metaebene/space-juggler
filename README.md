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

The package also contains **SpaceMouseKit**, the model catalog and report decoding, usable on its own.

## Supported devices

| Model | Vendor:Product | Buttons |
|---|---|---|
| SpaceMouse Compact | 256F:C635 | 2 |
| SpaceNavigator | 046D:C626 | 2 |
| SpaceMouse Pro | 046D:C62B | 15 |
| SpaceMouse Wireless (Bluetooth and on its cable) | 256F:C63A | 2 |

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
<directory>` builds it (`SIGN_IDENTITY` = your identity; `UNIVERSAL=1`, `TIMESTAMP=1` for distribution). The client
starts it through Launch Services when nobody answers.

## Parts

- `SpaceMouseKit` — models (IDs, buttons per model, LED, battery, serial number), input reports, the device state of
  3Dconnexion's classic client API.
- `SpaceJugglerProtocol` — the messages between Space Juggler and its clients (one JSON object per line over a Unix
  socket in `~/Library/Application Support/Space Juggler`), versioned.
- `SpaceJugglerClient` — what an app links.
- `SpaceJugglerCore`, `SpaceJuggler` — the broker and its menu bar app.
- `space-juggler-cli` — status, test clients and a broker without UI.

Design decisions: [docs/adr](docs/adr/README.md). Test runs: [docs/spike.md](docs/spike.md).

```
swift build
swift test
```

## Licence

MIT, see [LICENSE](LICENSE). SpaceMouse is a trademark of 3Dconnexion; this project is not affiliated with 3Dconnexion
and contains none of its code.
