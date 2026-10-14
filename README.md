# SpaceMouseKit

Shared support for the 3Dconnexion SpaceMouse family on macOS: the model catalog and report decoding, and
**Space Juggler**, a small broker that owns every attached SpaceMouse and hands it to one program at a time, so several
programs can use it side by side without the user caring which ones run. Every client app ships Space Juggler inside
its bundle; the newest one runs.

Status: early. The catalog joins what Kugelblitz and Stagehand know; the broker exists as a spike (`smk-spike`).
Steps: [docs/plan.md](docs/plan.md).

- `SpaceMouseKit` — models (vendor and product ID, buttons per model), input reports, the 3DxWare client API's
  device state.
- `SpaceMouseBroker` — who gets a SpaceMouse (`Arbiter`) and the wire protocol between Space Juggler and its clients.
- `smk-spike` — broker and client in one tool, to try the design (docs/spike.md).

Design: [docs/adr](docs/adr/README.md), starting with [ADR-0001](docs/adr/0001-space-juggler-owns-every-spacemouse.md).

| Model | Vendor:Product | Buttons |
|---|---|---|
| SpaceMouse Compact | 256F:C635 | 2 |
| SpaceNavigator | 046D:C626 | 2 |
| SpaceMouse Pro | 046D:C62B | 15 |
| SpaceMouse Wireless (Bluetooth and cable) | 256F:C63A | 2 |

```
swift build
swift test
```

SpaceMouse is a trademark of 3Dconnexion. This project is not affiliated with 3Dconnexion.
