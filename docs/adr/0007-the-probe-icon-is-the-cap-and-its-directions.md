# ADR-0007: Space Probe's icon is the cap and its directions, as Icon Composer layers

- Status: accepted (Tim, 2026-10-16)
- Date: 2026-10-16
- Related: ADR-0006 (the probe); Space Glider ADR-0010 (the same way of making an icon)

## Context

- Tim (2026-10-16): an Icon Composer icon for Space Probe, perhaps the drawing the probe shows of the cap.
- That drawing (`SpaceMouseTopView`) is a SpaceMouse from above: body, cap, side buttons, cable, and the twelve
  directions as SF Symbols. SF Symbols may not be used in app icons; side buttons and cable are too small at icon size.
- macOS 26 shows icons as layered Liquid Glass from an Icon Composer `.icon` package; `actool` compiles it into
  `Assets.car` and an `.icns` for older systems (as Space Glider does, its ADR-0010).

## Decision

- The icon is the drawing reduced to what the probe is about: the squircle as the SpaceMouse's dark body, the cap in
  the middle (brushed ring, rubber top) with the blue ring light, and around it what the probe asks for: four
  chevrons (slide), two curved arrows (twist), a dot (push), drawn here, not taken from SF Symbols.
- `Scripts/make-probe-icon.swift` draws three 1024×1024 layers and writes `App/Probe/AppIcon.icon`: `directions`
  (glass, specular), `cap` (no glass, neutral shadow), `body` (opaque). The package is committed; run the script again
  after changing it.
- `Scripts/build-space-probe.sh` compiles it with `actool` on every build; `Info.plist` names `AppIcon`.

## Consequences

- The icon can be refined in Icon Composer; changes made there are lost when the script runs again.
- The build needs Xcode's `actool` (26 or newer).

## Rules

- No SF Symbol artwork in the icon.

## Enforced and verified by

- `Scripts/make-probe-icon.swift`, `App/Probe/AppIcon.icon`, `Scripts/build-space-probe.sh`, `App/Probe/Info.plist`.
- 2026-10-16: `actool` compiles the package without warnings; the `.icns` shows the squircle with the glass marks.
