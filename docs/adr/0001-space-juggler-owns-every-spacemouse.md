# ADR-0001: Space Juggler, one broker, owns every SpaceMouse and gives it to one client at a time

- Status: accepted (Tim, 2026-10-14); broker built as a spike only (docs/spike.md)
- Date: 2026-10-14
- Related: ADR-0002 (the helper app), ADR-0003 (several SpaceMice), ADR-0004 (3DxWare); stagehand
  `docs/spacemouse-findings.md`

## Context

Four programs read the 3Dconnexion SpaceMouse, each with its own copy of the device code:

| Program | Wants the SpaceMouse | Before this ADR |
|---|---|---|
| Stagehand | always, in the background | seizes it permanently while listed |
| Kugelblitz | in front, optionally also in the background | seizes while active, or kept (its ADR-0155) |
| Space Shuttle (REAPER extension) | while REAPER is in front | seizes while REAPER is active; Compact only |
| Space Glider (menu bar agent) | while an app turned on in its menu is in front | seizes, or 3DxWare manual client |

- A seized HID device has exactly one owner. The programs coexisted only by taking turns on app activation and
  retrying (`SeizeClaim`); Stagehand blocked all others.
- The copies drifted: Kugelblitz knew four models, Space Glider three, Space Shuttle one; Stagehand had its own line.
- Each program handled the three forms of the 3Dconnexion driver on its own (ADR-0004).

## Decision

**Space Juggler** (the name, without additions: Tim, 2026-10-14) is a small broker program. It alone opens every
SpaceMouse and gives each to exactly one client. The four programs become its clients through this package.

- **Election.** A broker runs only while it holds `broker.lock` (`flock`, released when the process ends) and serves a
  Unix domain socket next to it (`~/Library/Application Support/Space Juggler/`).
- **The newest wins.** A broker that finds the lock taken asks the running one to hand over (`takeOver(version:)`); the
  running one releases its devices and leaves if, and only if, the newcomer's version is higher. A client that meets an
  older broker starts its own. A client that finds no broker starts the newest broker ever recorded (`newest.json`) if
  its program still exists, else its own. Updating one app brings its device support to all.
- **Claims.** A client says for which apps it wants the SpaceMouse while one of them is frontmost (its own app, the
  app it lives in, or the apps it steers) and whether it also wants it in the background.
- **Arbitration** (`Arbiter`):
  1. A claim naming the frontmost app beats every background claim. Among those, the frontmost process's own client
     beats a client steering that app from outside, then the earlier connection.
  2. Otherwise a background claim: whoever last had the SpaceMouse in front, then the earlier connection. A client
     that never claims a front app (Stagehand) thus always comes last (Tim, 2026-10-14).
  3. Nobody listens in: input goes to the holder only (Tim, 2026-10-14).
- **Seizing.** The broker seizes a SpaceMouse while somebody holds it and releases it otherwise.
- **Protocol.** One JSON object per line (`Wire`), versioned by `Wire.protocolVersion`; public, so other programs may
  be clients.
- **Model knowledge** lives only in the `SpaceMouseKit` library of this repository (IDs, buttons, reports, axes, LED,
  battery, serial number); it is public and also usable without the broker (probes, tests).

## Consequences

- Several programs use the SpaceMouse side by side, in front and in the background, without the user caring which run.
- A new model is added once, here; the next release of any client carries it to all.
- Every client depends on this package and on a broker process; when the broker crashes, input stops until a client
  starts a new one (measured: about 0.7 s).
- Input crosses a process boundary (about 60 Hz of small messages per device).
- The repository is public: findings describe observed behaviour only, never the vendor's confidential headers.

## Rules

- Only Space Juggler opens a SpaceMouse; clients never open one themselves (except for the driver case, ADR-0004).
- Who holds a SpaceMouse is decided only in `Arbiter`.
- Input goes to the holder only.
- A broker hands over only to a higher version.
- Model knowledge only in `SpaceMouseKit`.
- Never kill another process to get a device; never kill the 3Dconnexion helper.
- A change of the wire format that an older peer cannot read raises `Wire.protocolVersion`.

## Enforced and verified by

- `Arbiter`, `ArbiterTests`; `Wire`, `WireTests`; `BrokerPlace.recordNewest`.
- `Scripts/spike-scenario.sh` (2026-10-14, docs/spike.md): start on demand, front beats background, handover to v2,
  restart of the newest after `kill -9`, release when idle.
- Open: input at the device and following the frontmost app (docs/spike.md, run 2).
