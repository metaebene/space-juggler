# ADR-0008: Space Juggler's icon is its menu bar symbol, as Icon Composer layers

- Status: accepted (Tim, 2026-10-17)
- Date: 2026-10-17
- Related: ADR-0002 (the helper app and its menu bar item); ADR-0007 (Space Probe's icon, made the same way)

## Context

- Tim (2026-10-17): Space Juggler shows up in Activity Monitor without an icon; the symbol of the menu bar item
  should be its icon too.
- The bundle had no icon: an `LSUIElement` app has no Dock tile, but Activity Monitor, Finder and the privacy
  settings (Input Monitoring) show the bundle's icon.
- The menu bar symbol (`MenuBarIcon`) is a template image: one colour plus alpha, drawn at any scale.

## Decision

- The icon is the menu bar symbol, white, as a glass layer on a deep blue squircle (set apart from Space Probe's dark
  one).
- One drawing: `MenuBarIcon.draw(in:color:)` serves both. `Scripts/make-juggler-icon.swift` is compiled together
  with `Sources/SpaceJuggler/MenuBarIcon.swift` and writes `App/AppIcon.icon` with two 1024×1024 layers: `mark`
  (glass, specular) and `background` (opaque). The package is committed; run the script again after changing the
  symbol.
- `Scripts/build-space-juggler.sh` compiles it with `actool` on every build; `App/Info.plist` names `AppIcon`.

## Consequences

- A change to the menu bar symbol reaches the icon only when the script runs again.
- The build needs Xcode's `actool` (26 or newer), as Space Probe's does.

## Rules

- The icon's mark is the menu bar symbol, drawn by the same code.

## Enforced and verified by

- `Sources/SpaceJuggler/MenuBarIcon.swift`, `Scripts/make-juggler-icon.swift`, `App/AppIcon.icon`,
  `Scripts/build-space-juggler.sh`, `App/Info.plist`.
- 2026-10-17: `actool` compiles the package without warnings; `NSWorkspace` shows the icon for the built bundle.
