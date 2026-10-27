# Architecture decisions

| ADR | Title | Status |
|---|---|---|
| [0001](0001-space-juggler-owns-every-spacemouse.md) | Space Juggler, one broker, owns every SpaceMouse and gives it to one client at a time | accepted |
| [0002](0002-space-juggler-is-a-helper-app-inside-every-client.md) | Space Juggler is a helper app inside every client, started through Launch Services, with a menu bar item | accepted |
| [0003](0003-several-spacemice-each-on-or-off-acting-as-one.md) | Several SpaceMice are told apart by a fixed identity, each can be turned off, the others act as one | accepted |
| [0004](0004-space-juggler-is-the-drivers-one-manual-client.md) | While 3Dconnexion's helper runs, Space Juggler is the driver's one manual client | accepted |
| [0005](0005-a-spacemouse-the-catalog-does-not-know-is-still-a-spacemouse.md) | A SpaceMouse the catalog does not know is still a SpaceMouse | proposed |
| [0006](0006-the-probe-asks-until-a-model-is-known.md) | Space Probe asks at the device until a model is known | proposed |
| [0007](0007-the-probe-icon-is-the-cap-and-its-directions.md) | Space Probe's icon is the cap and its directions, as Icon Composer layers | accepted |
| [0008](0008-the-juggler-icon-is-the-menu-bar-symbol.md) | Space Juggler's icon is its menu bar symbol, as Icon Composer layers | accepted |
| [0009](0009-the-user-is-the-trust-boundary.md) | The user is the trust boundary; a peer is a stranger inside it | proposed |
| [0010](0010-a-cap-that-stays-off-its-centre-rests-there.md) | A cap that stays off its centre rests there: the holder gets the deflection from it | accepted |
| [0011](0011-the-menu-bar-item-is-for-developers.md) | Space Juggler's menu bar item is for developers and off by default | accepted |

Template: Context, Decision, Consequences, Rules, Enforced and verified by (as in the client repositories). A change
against an ADR's Rules needs a superseding ADR.
