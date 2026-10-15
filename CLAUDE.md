# Space Juggler (SpaceMouseKit) – Hinweise für Claude Code

Gemeinsame SpaceMouse-Unterstützung für Stagehand, Kugelblitz, Space Glider und Space Shuttle (öffentlich: github.com/metaebene/space-juggler, MIT):
Katalog und Dekodierung (`SpaceMouseKit`) und der Broker **Space Juggler** (Name ohne Zusätze, Entscheidung des Nutzers),
der jede SpaceMouse hält und an genau einen Client gibt. Schritte: `docs/plan.md`.
Sprache mit dem Nutzer: Deutsch. Code, Kommentare und Docs auf Englisch (CLAUDE.md deutsch). Swift 6, macOS 14+.

## Aufbau
- `Sources/SpaceMouseKit` – Modellkatalog (`SpaceMouseModel`: geprüft / veröffentlicht / geraten, ADR-0005),
  Report-Dekodierung, Report-Deskriptor-Parser (`HIDReportDescriptor`), rein. Was öffentliche Quellen über alle Modelle
  sagen: `docs/models.md`.
- `Sources/SpaceMouseKitUI` – SwiftUI-Zeichnung der SpaceMouse mit den zwölf Richtungen der Kappe (aus Stagehand).
- `Sources/SpaceJugglerProtocol` – Nachrichten (`Wire.swift`, eine JSON-Zeile je Nachricht über einen Unix-Socket),
  `BrokerPlace` (Sperre, Socket, Protokoll, `newest.json`), Socket-Hilfen.
- `Sources/SpaceJugglerCore` – der Broker: `Election`, `Devices` (IOKit), `Arbiter`, `Broker` (Server).
- `Sources/SpaceJugglerClient` – `SpaceJugglerConnection` für die Apps (verbinden, Broker starten, Anspruch, Ereignisse).
- `Sources/SpaceJuggler` – die App (Menüleiste); `Scripts/build-space-juggler.sh` baut und signiert `Space Juggler.app`.
- `Sources/space-juggler-cli` – Status, Test-Clients (`--raw`), `describe`, Broker ohne Oberfläche;
  `Scripts/spike-scenario.sh`, Läufe in `docs/spike.md`.
- `Sources/SpaceMouseProbe` – SpaceMouse Probe (Arbeitstitel, ADR-0006): fragt am Gerät Tasten, Achsen, LED und Etikett
  ab und schreibt einen Bericht fürs GitHub-Issue; `Scripts/build-spacemouse-probe.sh` (mit Space Juggler.app darin).
- Entscheidungen: `docs/adr/`. Hardware-Erkenntnisse stehen noch in Stagehand (`docs/spacemouse-findings.md`).

## Regeln (ADR-0001 … 0006)
- Nur Space Juggler öffnet eine SpaceMouse (seize); Clients nie. Läuft der 3Dconnexion-Helper, meldet sich Space
  Juggler als einziger manueller Treiber-Client an (`'++++'`, **immer mit Namen**, ohne stürzt Helper 1.4.4 ab),
  aktiviert ihn nur für einen Halter, bedient dann nur Ansprüche für die vordere App (ADR-0004).
- Space Juggler ist ein `LSUIElement`-Bundle in jeder Client-App (`me.metaebene.SpaceJuggler`), gestartet nur über
  Launch Services, nie als Kindprozess (eigene TCC-Identität, ADR-0002); er liest nur, erzeugt nie Ereignisse.
- Gerätedaten (Modell, Seriennummer, Akku) und die LED gehen an alle Clients, Eingaben nur an den Halter (ADR-0003).
- Wer sie bekommt, entscheidet nur `Arbiter`: Anspruch auf die vordere App schlägt Hintergrund; im Hintergrund, wer sie
  zuletzt vorn hatte; niemand liest mit.
- Es läuft genau ein Broker (`flock` auf `broker.lock`); der neueste gewinnt (Übergabe nur an eine höhere Version).
- Modellwissen nur in `SpaceMouseKit`; Geräte über Seriennummer, Bluetooth-Adresse oder Modell + USB-Port (+ Slot am
  Universal Receiver), nie über Namen oder Reihenfolge.
- Erkannt wird jeder Multi-axis Controller (1/8 in `DeviceUsagePairs`) von 046D/256F; ein Modell, das nicht `checked`
  ist, gilt nie ohne diesen Zusatz als unterstützt (ADR-0005). An Geräte wird nur die LED geschrieben, Feature-Reports
  nur gelesen.
- Nie einen anderen Prozess beenden, um an ein Gerät zu kommen; den 3Dconnexion-Helper nie.
- Öffentlich: Findings nur als beobachtetes Verhalten, nichts aus den vertraulichen Headern des Herstellers.

## Bauen und testen
- `swift build`, `swift test`; `Scripts/spike-scenario.sh` ergreift eine angeschlossene SpaceMouse für ~20 s.
- Version: `SpaceJuggler.version` in `Wire.swift` mit jedem Release erhöhen (der neueste Broker gewinnt). Release =
  SemVer-Tag (`git tag -a x.y.z`, pushen; nur den liest SwiftPM) **und** ein GitHub-Release zum Tag mit Release Notes
  für Menschen (`gh release create x.y.z --repo metaebene/space-juggler`). Die Apps ziehen mit
  `swift package update space-juggler` nach und committen ihr `Package.resolved`.
