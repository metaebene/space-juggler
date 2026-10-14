# Plan: from the spike to four clients

Each step ends with tests passing and, where it says so, a check by Tim at the device.

1. **Catalog complete** (done 2026-10-14) — `SpaceMouseKit` gets what Stagehand knows beyond Kugelblitz's copy: battery report 0x17,
   serial feature report 0x08 (Wireless), unknown button bits for diagnostics, LED properties per model (has one, needs
   the cable). Tests from both copies.
2. **Library split** (done 2026-10-14) — `SpaceJugglerProtocol` (today `SpaceMouseBroker`: `Wire`, `Arbiter`), `SpaceJugglerClient`
   (connect, start the newest broker through Launch Services, reconnect, claim; events for the app), the broker core
   (devices, identities, fleet, socket server) as a library the app target uses. The spike keeps working on top of it.
3. **Space Juggler.app** (built 2026-10-14; Launch Services and permissions checked, run 3) — `LSUIElement` bundle assembled and signed by `Scripts/build-space-juggler.sh`, menu bar item
   (devices, holder, waiting clients). A minimal host app starts it. **Tim:** permission dialogs and attribution
   (ADR-0002), input at the device, following the frontmost app, a released SpaceMouse (docs/spike.md, run 2).
4. **Device information and LED** — device list with battery and serial to all clients, LED from any client, on/off
   per device in the menu (ADR-0003). **Tim:** two SpaceMice, the Wireless on both transports.
5. **3DxWare** (done 2026-10-14, ADR-0004; runs 5 and 6) — `driver` state when the classic helper holds the device (ADR-0004). **Tim:** with the classic helper,
   with the DriverKit edition.
6. **Clients, one after another**, each with its accepted ADR and its own copy of `SpaceMouseKit` removed:
   Space Shuttle (smallest; gets every model), Kugelblitz (claim = own app, background setting; its fleet moves into
   Space Juggler), Space Glider (claim = the apps turned on), Stagehand (background claim, LED, battery; its own HID
   path for SpaceMice goes).
7. **Public** (done 2026-10-14: github.com/timpritlove/space-juggler, MIT, tag 0.2.0; findings stay in Stagehand for now) — licence, findings moved here and reviewed (no vendor header text), first tagged release.
