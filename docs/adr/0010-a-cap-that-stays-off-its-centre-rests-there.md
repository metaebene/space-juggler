# ADR-0010: A cap that stays off its centre rests there

- Status: accepted (Tim, 2026-10-25)
- Date: 2026-10-25
- Related: ADR-0001, ADR-0003, ADR-0004; Kugelblitz ADR-0485 (a cap held when a flight begins does not stop it)

## Context

- A problem report of Kugelblitz (2026-10-25, an old SpaceNavigator, 046D:C626, seized raw): the cap, untouched, kept
  reporting a small deflection just beyond Kugelblitz's dead zone (28 of 350 units). Kugelblitz saw a hand that never
  let go: the camera moved by an invisible little, and every flight ended in its first frame.
- 3Dconnexion's driver zeroes such a rest itself. Space Juggler reads the device raw (ADR-0001) and passed the
  deflection on as it came, to every client; each client would have to find the rest on its own.
- A device in its middle reports all zeros once and then nothing; a deflected one reports about every 16 ms, even
  while the deflection stays the same.

## Decision

- Every seized device has a `CapRest` (in `SpaceMouseKit`, pure): a deflection that stays within `wobble` (4 units
  per axis) for `settle` (1.5 s), no farther than `reach` (a sixth of the full scale) from the centre, becomes the
  cap's rest. What goes to the holder is the deflection from the rest; around the rest its wobble counts as rest.
- A report of all zeros takes the rest back to zero: the device itself says it is in the middle.
- The broker logs every new rest per device.
- Input through 3Dconnexion's driver (ADR-0004) is left as it comes: the driver zeroes it already.

## Consequences

- Clients see zero from a cap nobody touches, whatever its rest; a dead zone stays theirs.
- A hand holding the cap that still for 1.5 s close to the centre would be taken as rest; letting go then leaves a
  small deflection the other way for another 1.5 s. Hands wobble more than 4 units, so this should be rare.
- Raw reports (`--raw`, Space Probe's report) stay as the device sent them.

## Rules

- The axes a holder gets from a seized device are the deflection from its rest, only through `CapRest`.
- A rest is taken only from a deflection that stayed within `wobble` for `settle` and within `reach`; all zeros reset it.

## Enforced and verified by

- `CapRest`, `Reports.ingest`.
- `CapRestTests`, `ReportsTests.aCapRestingOffItsCentreIsPassedOnAsAtRest`.
- On the device, open: an old SpaceNavigator left alone off its centre; the broker's log names its rest, the client
  sees zero.
