# ADR-0012: A failed registration with 3Dconnexion's driver is tried again, ever less often and logged ever more rarely

- Status: accepted (Tim, 2026-11-05)
- Date: 2026-11-05
- Related: ADR-0004 (amended here); Kugelblitz ADR-0768 (the problem report that carries this log)

## Context

- While 3Dconnexion's helper runs, Space Juggler does not seize and registers with the driver instead (ADR-0004). A
  registration that failed was logged once and never tried again: Space Juggler stayed in driver mode without a client
  of the driver, so no app got any input, until the helper quit or started again.
- `SetConnexionHandlers` returns -36 when no helper answers (Space Shuttle, release 0.1). On Tim's Mac on 2026-11-04,
  four of six brokers that started while NSWorkspace listed the helper got -36 (03:53, 11:57, 12:13, 12:15), each
  shortly after a restart or a login; the one started at 12:33, a second after a fresh helper, registered. From
  2026-10-25 to 2026-11-03 nine registrations went through. Why the listed helper did not answer is not known.
- A Kugelblitz user reported (2026-11-04): with the driver installed the SpaceMouse did nothing; without it, it worked.
  That this was the case is likely, not shown.
- Tim (2026-11-05): fix it; the log must not fill up when the failure goes on, the tries may grow further apart.
- Amended 2026-11-07 (version 13): with version 12 every try after a -36 returned -188, on Tim's Mac 32 times over
  45 min while the helper ran (broker 00:46, helper 1.4.4), and Kugelblitz said "connected" while the SpaceMouse did
  nothing. The framework counts a failed `SetConnexionHandlers` as set and refuses every later call ("called multiple
  times without a following call to RegisterConnexionClient()"); measured with a probe: -36, then -188, after
  `CleanupConnexionHandlers` -36 again, i.e. a real attempt.

## Decision

- **`DriverRetry`** (pure) decides after every failed registration – framework not loadable, `SetConnexionHandlers`
  not 0, no client ID, another client in the process – when to try again: after 2, 5, 10, 30 s, 1, 2, 5, 10 min, then
  every 30 min while the helper runs.
- **An app that wants the SpaceMouse brings the next try forward**: when the broker wants the driver for a holder
  (`DriverClient.want(true)`) while not registered, it tries at once, but no sooner than 10 s after the last try. So
  a user who brings an app to the front gets the SpaceMouse as soon as the driver answers, even when the next try was
  half an hour away.
- **The log stays small**: a failure is logged when it is the first, when its reason differs from the last one logged,
  and otherwise only the 2nd, 4th, 8th … with how often it failed and when it tries next ("driver:
  SetConnexionHandlers returned -36, failed 8 times; trying again in 10 min"); a day of failures writes about a dozen
  lines. A registration after failures says how many there were.
- **A failed `SetConnexionHandlers` is cleaned up** (`CleanupConnexionHandlers`) before the next try, as a missing
  client ID already was (amended 2026-11-07).
- The helper going away (`stop`) ends the tries and starts the count afresh; its return starts them again as before
  (`registrationDelay`).

## Consequences

- A driver that answers late is used without restarting anything; the first try after a login no longer decides the
  whole session.
- While it does not answer, the SpaceMouse still does nothing (Space Juggler does not seize while the helper is listed:
  what the helper does with a device seized before it is not measured, `docs/3dxware-package.md`), but the log says
  so and keeps trying.
- Clients do not change; the protocol stays 2.

## Rules

- After a failed registration Space Juggler tries again, scheduled only by `DriverRetry`, never more often than its
  delays and `soonest`.
- A failure is logged only when `DriverRetry` returns a line.
- Every failure after `SetConnexionHandlers` was called ends with `CleanupConnexionHandlers` before the next try.

## Enforced and verified by

- `Sources/SpaceJugglerCore/DriverRetry.swift`; `DriverClient.failed`, `schedule`, `want`, `stop`, `register` (the
  cleanup after both failures).
- `Tests/SpaceJugglerTests/DriverRetryTests.swift`: the delays, the logged failures of a thousand (1, 2, 4 … 512), a new
  reason at once, the early try and its limit, the fresh start after success.
- Open at the device: a broker that got -36 and registered on a later try (seen only when it happens again; the
  helper is never stopped to provoke it).
