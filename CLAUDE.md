# Netzblick – Kontext für Claude

iPhone-App, die das Heimnetz über die FRITZ!Box verständlich macht. Alles lokal, kein Server,
kein Konto. Eigentümer: Johann. Arbeitssprache mit ihm: Deutsch, direkt und knapp.
Technischer Aufbau und Regeln: siehe `ARCHITECTURE.md` (verbindlich).

## Stand (19.10.2026)

- Kern (`Packages/NetzblickKit`), App-Screens, Widgets und CI sind gebaut. CI auf GitHub (macOS) ist grün:
  Kit-Tests laufen, App und Widgets kompilieren.
- Noch nie auf einem Gerät oder gegen eine echte FRITZ!Box gelaufen. Annahmen über Box-Antworten
  stehen als `// VERIFY:` im Code.
- Johann muss selbst: Team unter Signing eintragen, App Group `group.com.johann255.netzblick` anlegen.
- Hier gibt es kein Xcode: Bauen und Prüfen nur über die CI. Fehler kommen als Check-Run-Annotationen
  (xcbeautify `--renderer github-actions`), weil die Job-Logs nicht erreichbar sind.

## Begleitmaterial

- Plan bis App Store (Doc): https://claude.ai/code/artifact/86af7750-53f7-49c3-9f32-337da7cddfd4
- Design-Mockup (Canvas): https://claude.ai/artifact/YMS7H4CPZCtZA5JHsjyCtq

## Getroffene Entscheidungen

- v1.0 kostenlos, Ziel Ende Januar 2027. v1.0 ändert nichts an der FRITZ!Box; Findings erklären die Schritte.
- Designsprache: Akzentblau als Fläche (Ultramarin/Nachtblau/Himmelblau wählbar), Instrument Serif
  für Überschriften und große Zahlen, Geist für Text.
- Tempo-Test in v1.0 mit Ampel: mit Tarif grün ab 90 %, gelb 50–90 %, rot darunter;
  ohne Tarif rot unter 15 Mbit/s, grün ab 50. Einziger Kontakt zu einem externen Server.
- Testserver (19.10.2026): M-Lab ndt7 (Locate v2 + WebSocket-Download, ~10 s, eine Verbindung). M-Lab veröffentlicht
  jede Messung mit IP-Adresse; das steht vor dem Start im Tempo-Test-Sheet und im Grenzen-Text. Datensparsam:
  kein client_name, keine Version, User-Agent „ndt7“. Server (Stadt) wird angezeigt und mit dem Ergebnis gespeichert.
  Noch prüfen: App-Store-Datenschutzangaben (Datenweitergabe an M-Lab).
- Widgets in v1.0: Status, Übersicht, Tempo, Sperrbildschirm. Lesen nur aus der App Group.
- Grenzen-Text in den Einstellungen ist Pflicht und muss zum Verhalten passen.
- v1.1: DNS-Lauschmodus (Paketmitschnitt der Box) und Geräteprofile mit Sperr-Empfehlungen
  (lokal mitgelieferte Domainlisten in drei Gruppen: kann gesperrt werden / besser laufen lassen / nie sperren).
- Marke: kein „FRITZ!“ in App-Name oder Icon. Tracker-Listen nur mit Lizenz für kommerzielle Nutzung
  (DuckDuckGo Tracker Radar ist CC BY-NC-SA, also nicht nutzbar).

## Offene Fragen und Vorschläge (nicht entschieden)

1. ~~Testserver~~ – entschieden: M-Lab (siehe oben).
2. **FRITZ!-DNS-Filter** (FRITZ!OS 8.50 Labor): keine bekannte App-Schnittstelle. Vorschlag: Netzblick-Sperrliste
   und Ausnahmeliste als statische Dateien zum Abonnieren; prüfen, ob die Labor-Firmware einen neuen TR-064-Dienst zeigt.
   Später gemeinsame Schicht „Sperrziel“ (FRITZ!-Zugangsprofil, FRITZ!-DNS-Filter, Pi-hole).
3. **Andere Router**: FRITZ!Box ~51 %, Telekom ~19 %, Vodafone ~10 % (YouGov 2025, im Auftrag von FRITZ!).
   Speedport und Vodafone Station haben keine offizielle Schnittstelle. Vorschlag: nach v1.0 erst Vodafone,
   für alle anderen ein Basis-Modus (Bonjour + Tempo-Test).
4. **Android**: Vorschlag „Daten statt Code teilen“ – Regeln, Herstellertabelle, Diagnose-Texte, Schwellen und
   Geräteprofile als JSON, gemeinsame Box-Fixtures als Testfälle, nativer Kotlin-Kern + Compose-UI.
   Johann hat noch nicht zugestimmt. Erster Schritt erledigt (19.10.2026): `RouterAdapter`-Protokoll im Kit
   (`Router/RouterAdapter.swift`), `FritzBoxReader` und `DemoRouter` erfüllen es, `AppModel` kennt nur `any RouterAdapter`.
   Offen: Zeitpunkt der JSON-Auslagerung (Empfehlung: nach v1.0). Einzige FRITZ!-Bindung oberhalb des Adapters
   sind die Diagnose-Texte (`DiagnosisEngine`, „FRITZ!Box“/„fritz.box“) – die müssten pro Router austauschbar werden.

5. **Fing/Fingbox-Funktionen** (19.10.2026): Plan in `docs/fing-plan.md`. Phase 1–3 (Sicherheits-Check,
   Geräteverlauf + Wachhund, Werkzeuge: Ping, offene Dienste, Kameras, Aufwecken) in PR #2.
   Offen: Aufwecken über die Box schon in v1.0? Wachhund standardmäßig aus?

## Nächster Schritt

Johann startet die App im Simulator (Demo) und auf dem iPhone gegen seine Box, schickt Screenshots;
danach `VERIFY`-Stellen abhaken und Screens am Gerät feinschleifen.

## Arbeitsweise

- Einfache, klar abgegrenzte Aufgaben (Views nach Vertrag, Konfigurationsdateien, Kopierarbeit) an Haiku-Subagenten
  geben; Kern-Logik, Schnittstellen und Review selbst machen.
- Commits als „Johann <johann.neubert@posteo.de>“ mit Co-Authored-By-Zeile, direkt auf `main`.
