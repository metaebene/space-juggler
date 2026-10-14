# ADR-0004: Space Juggler alone finds out what the 3Dconnexion driver allows; with the classic helper, clients use the driver themselves

- Status: proposed; to be measured with each form of the driver
- Date: 2026-10-14
- Related: ADR-0001; stagehand `docs/spacemouse-findings.md` ("Routing", "Re-implementation options")

## Context

The 3Dconnexion driver comes in three forms (stagehand findings):

| Form | The device | The driver's client API |
|---|---|---|
| none installed | free; a seize succeeds | — |
| DriverKit edition (dext, 3DxNLServer, no 3DconnexionHelper) | a seize succeeded with no error (2026-10-06) | what its apps get meanwhile is not measured |
| classic 3DconnexionHelper | the helper holds it exclusively; every other open fails with `kIOReturnExclusiveAccess` | routes to the frontmost app's client (`'****'`); a background client gets data only as manual client (`'++++'` + `'3dac'`), which starves the frontmost app |

- Every client must be able to use the SpaceMouse in front in every case; background use may be impossible in some
  (Tim, 2026-10-14).
- Helper 1.4.2 crashed after a `'++++'` registration from Space Glider's app bundle (Space Glider `docs/feasibility.md`).
- Kugelblitz and Space Shuttle already work as ordinary `'****'` clients.

## Decision

- Space Juggler tries to seize. If that fails with `kIOReturnExclusiveAccess` while the 3Dconnexion helper runs, it
  tells its clients `driver` instead of granting input.
- A client told `driver` registers with the driver itself as an ordinary `'****'` client of its own app (the code in
  `SpaceMouseKit`), so the frontmost app works; background claims get nothing. When the helper is gone, Space Juggler
  seizes again and tells clients to unregister.
- Space Juggler itself never registers with the driver and never loads its framework.
- Space Glider, which steers other apps, would need `'++++'` here; that stays its own decision (known crash).

## Consequences

- With the classic helper, the behaviour is today's: each program gets the SpaceMouse while it is in front.
- The DriverKit edition is treated like "none" until a measurement says otherwise.

## Rules

- Only Space Juggler decides between seizing and the driver; a client registers with the driver only when told.
- Never kill the 3Dconnexion helper.

## Enforced and verified by

Open checks: with the classic helper (Space Juggler says `driver`, Kugelblitz in front steers through the driver);
with the DriverKit edition (do Blender or 3Dconnexion's Trainer still work while Space Juggler holds the device?).
