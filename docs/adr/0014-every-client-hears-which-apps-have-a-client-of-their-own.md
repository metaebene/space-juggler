# ADR-0014: Every client hears which apps have a client of their own

- Status: proposed
- Date: 2026-11-07
- Related: ADR-0001 (arbitration: the frontmost process's own client first); Space Glider ADR-0026, ADR-0029, ADR-0051

## Context

- Space Glider steers other apps and claims the apps the user turned on in its menu. For an app with a client of its
  own, Kugelblitz or REAPER with Space Shuttle, the claim never wins (ADR-0001, `Arbiter.decide`). Space Glider's menu
  still offered "Use the SpaceMouse in Kugelblitz", and turning it on did nothing (Tim, 2026-11-07).
- Only the broker knows which clients there are: their process IDs and their claims. A client heard only the devices
  and whether it holds; `status` tells more, but as an answer to a question, which a menu that opens at once cannot
  wait for.
- A declaration in the app's Info.plist would also cover apps that are not running, but it would be wrong whenever the
  app does not use the SpaceMouse (Kugelblitz without one connected to Space Juggler), and other programs would have to
  adopt it.

## Decision

- An app **has a client of its own** when a client's process is that app (the bundle ID of its process ID, through
  `NSRunningApplication`) and its claim names the app. It is the same client that `Arbiter.decide` lets beat one
  steering the app from outside. Kugelblitz is its own; Space Shuttle is REAPER's (it runs in REAPER's process);
  Stagehand is its own while it claims itself; Space Glider is its own only for its own window.
- `Arbiter.appsWithOwnClient` (pure) works this out from the claimants. The broker tells every client the list as
  `BrokerMessage.appsWithOwnClient(apps:)` right after the welcome and whenever a claim comes, changes or goes and the
  list changes. `BrokerStatus.appsWithOwnClient` carries it too.
- `SpaceJugglerConnection.appsWithOwnClient` holds it (empty while not connected and from an older broker), and
  `onAppsWithOwnClient` reports changes. That is a callback of its own, not a new `Event`, so that apps that switch over
  every event keep compiling.
- The protocol stays 2: an older client drops the line unread (`LineDecoder` skips a line it cannot decode), and a
  client of an older broker hears nothing, so it stays as it was. `SpaceJuggler.version` goes to 15.

## Consequences

- Space Glider can grey out an app that steers itself, as long as that app runs, which is when its menu names it.
- An app whose own support goes through 3Dconnexion's driver and not through Space Juggler (Blender, Fusion) is not
  known here. Space Glider's own list (`excluded_apps`) stays for them.
- Who holds the SpaceMouse does not change: `Arbiter.decide` alone decides that.

## Rules

- Which apps have a client of their own is decided only in `Arbiter.appsWithOwnClient` and told only through
  `appsWithOwnClient`.
- A client reads it as a hint for its own interface, never as a reason to change its claim behind the user's back.

## Enforced and verified by

- `Arbiter.appsWithOwnClient`; `Broker.updateAppsWithOwnClient` and its `bundleID` lookup;
  `SpaceJugglerConnection.appsWithOwnClient`, `onAppsWithOwnClient`; the CLI client prints the list.
- `ArbiterTests.appsWithOwnClientAreTheProcessesThatClaimThemselves`;
  `BrokerTests.everyClientHearsWhichAppsHaveAClientOfTheirOwn` (the list as a client comes and goes, also to the client
  itself) and `anOlderClientDropsTheMessageUnread`.
- Open: with the real apps, Kugelblitz and REAPER with Space Shuttle each named while running, gone once they quit.
