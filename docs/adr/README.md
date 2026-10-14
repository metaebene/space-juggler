# Architecture decisions

| ADR | Title | Status |
|---|---|---|
| [0001](0001-space-juggler-owns-every-spacemouse.md) | Space Juggler, one broker, owns every SpaceMouse and gives it to one client at a time | accepted |
| [0002](0002-space-juggler-is-a-helper-app-inside-every-client.md) | Space Juggler is a helper app inside every client, started through Launch Services, with a menu bar item | proposed |
| [0003](0003-several-spacemice-each-on-or-off-acting-as-one.md) | Several SpaceMice are told apart by a fixed identity, each can be turned off, the others act as one | accepted |
| [0004](0004-the-3dconnexion-driver-is-space-jugglers-business.md) | Space Juggler alone finds out what the 3Dconnexion driver allows; with the classic helper, clients use the driver themselves | proposed |

Template: Context, Decision, Consequences, Rules, Enforced and verified by (as in the client repositories). A change
against an ADR's Rules needs a superseding ADR.
