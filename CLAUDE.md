# SpaceMouseKit – Hinweise für Claude Code

Gemeinsame SpaceMouse-Unterstützung für Stagehand, Kugelblitz, Space Glider und Space Shuttle (öffentliches Repo):
Katalog und Dekodierung (`SpaceMouseKit`) und der Broker **Space Juggler** (Name ohne Zusätze, Entscheidung des Nutzers),
der jede SpaceMouse hält und an genau einen Client gibt. Schritte: `docs/plan.md`.
Sprache mit dem Nutzer: Deutsch. Code, Kommentare und Docs auf Englisch (CLAUDE.md deutsch). Swift 6, macOS 14+.

## Aufbau
- `Sources/SpaceMouseKit` – Modellkatalog und Report-Dekodierung (Kugelblitz' `SpaceMouseValues.swift` plus Akku,
  Seriennummer, unbekannte Bits und LED-Eigenschaften aus Stagehand), rein.
- `Sources/SpaceMouseBroker` – `Arbiter` (wer bekommt die SpaceMouse), Protokoll (`Wire`, eine JSON-Zeile je
  Nachricht über einen Unix-Socket), Socket-Hilfen.
- `Sources/smk-spike` – Broker und Client in einem Werkzeug; `Scripts/spike-scenario.sh`, Ergebnisse in `docs/spike.md`.
- Entscheidungen: `docs/adr/`. Hardware-Erkenntnisse stehen noch in Stagehand (`docs/spacemouse-findings.md`).

## Regeln (ADR-0001 … 0004)
- Nur Space Juggler öffnet eine SpaceMouse (seize); Clients nie (Ausnahme: Treiber-Fall, ADR-0004).
- Space Juggler ist ein `LSUIElement`-Bundle in jeder Client-App (`me.metaebene.SpaceJuggler`), gestartet nur über
  Launch Services, nie als Kindprozess (eigene TCC-Identität, ADR-0002); er liest nur, erzeugt nie Ereignisse.
- Gerätedaten (Modell, Seriennummer, Akku) und die LED gehen an alle Clients, Eingaben nur an den Halter (ADR-0003).
- Wer sie bekommt, entscheidet nur `Arbiter`: Anspruch auf die vordere App schlägt Hintergrund; im Hintergrund, wer sie
  zuletzt vorn hatte; niemand liest mit.
- Es läuft genau ein Broker (`flock` auf `broker.lock`); der neueste gewinnt (Übergabe nur an eine höhere Version).
- Modellwissen nur in `SpaceMouseKit`; Geräte über Seriennummer, Bluetooth-Adresse oder Modell + USB-Port, nie über
  Namen oder Reihenfolge.
- Nie einen anderen Prozess beenden, um an ein Gerät zu kommen; den 3Dconnexion-Helper nie.
- Öffentlich: Findings nur als beobachtetes Verhalten, nichts aus den vertraulichen Headern des Herstellers.

## Bauen und testen
- `swift build`, `swift test`; `Scripts/spike-scenario.sh` ergreift eine angeschlossene SpaceMouse für ~20 s.
