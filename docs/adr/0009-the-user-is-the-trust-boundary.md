# ADR-0009: The user is the trust boundary; a peer is a stranger inside it

- Status: proposed (from the security review of 2026-10-23)
- Date: 2026-10-23
- Related: ADR-0001 (one broker, the socket), ADR-0002 (started through Launch Services, `disable-library-validation`),
  ADR-0004 (3Dconnexion's client framework)

## Context

- Space Juggler runs per user: lock, socket, log and `newest.json` live in `~/Library/Application Support/Space
  Juggler`. Any process of that user can connect to the socket, claim the SpaceMouse, switch an LED or ask for a
  description; nothing authenticates a client, and the messages are JSON lines from whoever connected.
- `newest.json` names a program a client starts when no broker answers (ADR-0001). An app that starts a command-line
  broker from it would spawn a child process, which ADR-0002 forbids for apps; a test that left a CLI record behind
  would make every app do so.
- Space Juggler loads `/Library/Frameworks/3DconnexionClient.framework`, signed by another team, under
  `disable-library-validation` (ADR-0002, ADR-0004). `/Library/Frameworks` is writable by administrators only.
- The log carries serial numbers; the socket is the way to the SpaceMouse.
- A peer that stops reading was already handled (`LineConnection.backlogLimit`, 2026-10-20); a peer whose line never
  ends was not: the decoder's buffer grew without bound.

## Decision

- Everything that runs as the user is trusted to *use* Space Juggler: there is no authentication at the socket, no
  secret, no capability check. A process of the same user holds every privilege Space Juggler has anyway; a check
  would only pretend otherwise.
- A peer is still a stranger to the *code*: what it sends is parsed defensively (one JSON object per line, unknown
  lines dropped, `backlogLimit` on what it does not read, `lineLimit` on a line it never ends), and nothing it sends is
  executed or written anywhere but the device's LED.
- `newest.json` is advice, not authority: a client starts an app from it only if the bundle at that path is Space
  Juggler by its bundle identifier, and a command-line broker from it only if the client spawns command-line brokers
  itself (tests and the CLI).
- The directory is the user's alone (`0700`); the socket and the lock are `0600`.
- The framework is loaded from its fixed path under `/Library/Frameworks` only, never from a path a peer or a file
  names.

## Consequences

- A malicious process of the same user can take the SpaceMouse from an app. That is the user's own account and the
  same as with any input device; it is not Space Juggler's to prevent.
- Other local users cannot connect, read the log or learn the serial numbers.
- A stale or forged `newest.json` can at worst start the user's own Space Juggler, or nothing.

## Rules

- Nothing read from the socket or from `newest.json` is executed, spawned or opened, except an app bundle that is
  Space Juggler by identifier, from `newest.json`, through Launch Services.
- Every bound on a peer (`backlogLimit`, `lineLimit`) closes the connection; nothing blocks, nothing grows without
  bound.
- Files under the broker's directory are made by Space Juggler with the user as their only reader.

## Enforced and verified by

- `BrokerPlace.ensureDirectory` (`0700`), `UnixSocket.listen` (`0600`), `Election.run` (`0600` lock).
- `BrokerPlace.Newest.isUsable`, `SpaceJugglerConnection.launch`.
- `LineConnection.backlogLimit` and `lineLimit`, `ConnectionTests`.
- `DriverClient.frameworkPath`.
