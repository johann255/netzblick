# Netzblick – Architektur

iOS-App (SwiftUI, iOS 17+), die das Heimnetz über die FRITZ!Box verständlich macht.
Alles läuft lokal auf dem iPhone. Es gibt keinen Netzblick-Server.

## Aufbau

```
Netzblick/
├── project.yml                 XcodeGen-Projektdefinition (Xcode-Projekt wird generiert)
├── App/                        iOS-App (SwiftUI)
│   ├── NetzblickApp.swift      Einstieg
│   ├── AppModel.swift          Zentraler Zustand (@Observable)
│   ├── Theme/                  Designsystem: Farben, Schriften, Bausteine
│   ├── Features/<Screen>/      Ein Ordner pro Screen
│   ├── Services/               Schlüsselbund, Bonjour, Speicher
│   └── Resources/Fonts/        Instrument Serif, Geist (SIL OFL)
└── Packages/NetzblickKit/      Plattformneutrale Logik, per `swift test` testbar
    ├── Model/                  Device, HouseholdSnapshot, Finding, Speed
    ├── TR064/                  SOAP-Client für die FRITZ!Box
    ├── Classification/         Gerätekategorie aus Name, Hersteller, Bonjour
    ├── Diagnosis/              Regeln, die Findings erzeugen
    └── Demo/                   Demo-Haushalt (Pflicht für das App-Review)
```

## Regeln

- **Logik gehört ins Kit, Darstellung in die App.** Views rechnen nichts aus, was testbar sein sollte.
- **Texte für Nutzer sind Deutsch**, kurz, ohne Fachjargon. Code, Kommentare und Bezeichner sind Englisch.
- **Keine Drittanbieter-Abhängigkeiten** ohne Absprache. Kein Analytics, kein Crash-SDK.
- **v1.0 ändert nichts an der FRITZ!Box.** Findings erklären die Schritte (`Finding.howTo`).
- **Gastnetz-Geräte** werden gezählt, aber nie im Detail ausgewertet.
- Swift 5.10, `async/await`, Typen im Kit sind `Sendable`.

## Designsystem (Vertrag für `App/Theme`)

Alle Screens nutzen nur diese Namen. Farben passen sich hell/dunkel an.

| Name | Hell | Dunkel | Zweck |
| --- | --- | --- | --- |
| `Color.nbPaper` | #F6F5F0 | #0C0F1E | Seitenhintergrund |
| `Color.nbCard` | #FFFFFF | #161A2E | Karten |
| `Color.nbInk` | #0B1352 | #F2F3F8 | Haupttext |
| `Color.nbInkSoft` | #2E3555 | #C9CCDA | Fließtext |
| `Color.nbMuted` | #5A607A | #A3A8BF | Nebentext |
| `Color.nbLine` | #ECEDF2 | #262B44 | Trennlinien |
| `Color.nbTint` | #E3E7FB | #1E2550 | Hinweis-Hintergrund (blau) |
| `Color.nbTintInk` | #1A2A9C | #B9C2FF | Hinweis-Text (blau) |
| `Color.nbWarnBg` | #FCEBDD | #3A2412 | Warn-Chip-Hintergrund |
| `Color.nbWarn` | #9A4206 | #F3B07A | Warn-Chip-Text |
| `Color.nbOrange` | #E07B28 | #E8893A | Punkte, Tracking-Anteil |
| `Color.nbGray` | #BFC3D3 | #4A5070 | Neutraler Anteil |
| `Color.nbDanger` | #B42318 | #FF8A80 | Destruktive Aktionen |
| `Color.nbOnBlueMuted` | #D3D8FA | #D3D8FA | Nebentext auf blauer Fläche |
| `Color.nbSpeedSlow` | #C62828 | #EF5350 | Tempo rot |
| `Color.nbSpeedOk` | #D69E00 | #F2C14E | Tempo gelb |
| `Color.nbSpeedFast` | #1E8E5A | #4CC38A | Tempo grün |

Akzentblau ist wählbar (`AccentBlue`, gespeichert unter `@AppStorage("accentBlue")`):
Ultramarin #2133D0 (Standard), Nachtblau #16226E, Himmelblau #1F62D6. Es ist über
`@Environment(\.nbAccent)` lesbar.

Schrift:
- `Font.nbSerif(_ size: CGFloat, italic: Bool = false)` – Instrument Serif, für Überschriften und große Zahlen.
- `Font.nbSans(_ size: CGFloat, weight: Font.Weight = .regular)` – Geist, für alles andere.
- Fehlt eine Schriftdatei, fallen beide auf die Systemschrift zurück.
- Interne Namen: `InstrumentSerif-Regular`, `InstrumentSerif-Italic` (PostScript), `Geist`
  (Familie einer variablen Schrift; Gewicht per `.weight(_:)`). Dateien liegen in `App/Resources/Fonts`.

Bausteine:
- `NBScreen(header:content:)` – blaue Kopffläche oben, Inhalt überlappt sie um 48 pt, scrollt als Ganzes.
- `NBBlueHeader(eyebrow:title:italicTail:subtitle:)` – Kopffläche in Akzentblau, Titel Serif 46–56 pt.
- `NBCard { … }` – weiße Karte, Radius 20, weicher Schatten.
- `NBSectionTitle(_ text:)` – Serif 28 pt über einer Karte.
- `NBRow(symbol:title:subtitle:trailing:)` – Listenzeile mit Icon-Kachel 40×40.
- `NBChip(_ text:style:)` – `.warn` (orange) oder `.tip` (blau).
- `NBSegmentBar(segments:)` – Balken aus Anteilen, z. B. Normal / Tracking / Hersteller.
- `NBPrimaryButtonStyle`, `NBSecondaryButtonStyle` – Höhe 44 pt, Radius 12.

## FRITZ!Box-Schnittstelle (TR-064)

- Beschreibung: `http://<box>:49000/tr64desc.xml` listet Dienste mit `serviceType` und `controlURL`.
- Aufruf: SOAP-POST an `controlURL`, Header `SOAPACTION: "<serviceType>#<Action>"`.
- Anmeldung: HTTP Digest. Auf Apple-Plattformen übernimmt `URLSession` das über `URLCredential`.
- Genutzte Aktionen (v1.0): `DeviceInfo:1#GetInfo`, `UserInterface:1#GetInfo`,
  `Hosts:1#X_AVM-DE_GetHostListPath`, `WLANConfiguration:n#GetInfo`,
  `WLANConfiguration:n#X_AVM-DE_GetWLANDeviceListPath`, `WANCommonInterfaceConfig:1#GetCommonLinkProperties`,
  `WANCommonInterfaceConfig:1#GetAddonInfos` (Live-Auslastung).
- Felder werden tolerant gelesen: Fehlt ein Feld, bleibt der Wert `nil`. Was an einer echten Box
  noch zu bestätigen ist, steht als `// VERIFY:` im Code.

## Tempo

`SpeedRating.rate(downloadMbps:bookedMbps:)` bewertet eine Messung als rot, gelb oder grün:
mit bekanntem Tarif relativ dazu (ab 90 % grün), sonst absolut (unter 15 Mbit/s rot, ab 50 grün).
`BottleneckVerdict.judge` vergleicht iPhone-Messung und Leitungstempo der Box.

## Widgets

- Eigene Erweiterung `NetzblickWidgets` (Ordner `Widgets/`), teilt `App/Theme` mit der App.
- Datenfluss: Die App schreibt nach jedem Abruf ein `WidgetSummary` als JSON in die App Group
  `group.com.johann255.netzblick` (Datei `widget-summary.json`) und ruft
  `WidgetCenter.shared.reloadAllTimelines()`. Widgets lesen nur, sprechen nie mit der Box.
- Größen: klein (Status), mittel (Geräte, Neu, Tempo), Sperrbildschirm (rechteckig und rund).

## Bauen

- Kit: `cd Packages/NetzblickKit && swift test`
- App: `brew install xcodegen && xcodegen generate && open Netzblick.xcodeproj`
- CI: GitHub Actions auf macOS (`.github/workflows/ci.yml`)
