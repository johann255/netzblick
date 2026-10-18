# Netzblick

Netzblick ist eine iPhone-App, die das Heimnetz über die FRITZ!Box verständlich macht: Welche Geräte sind online, wer verbraucht gerade Bandbreite, wo hakt das Netz. Alles läuft lokal auf dem iPhone. Es gibt keinen Netzblick-Server, und Daten verlassen das Gerät nicht.

## Loslegen

**Voraussetzungen:** Xcode 16 oder neuer, [Homebrew](https://brew.sh).

```sh
brew install xcodegen
xcodegen generate
open Netzblick.xcodeproj
```

- In Xcode unter **Signing & Capabilities** dein Team eintragen.
- Für die Widgets muss die App Group `group.com.johann255.netzblick` in deinem Apple-Developer-Account existieren.
- Ohne FRITZ!Box kannst du die App im **Demo-Modus** starten.

## FRITZ!Box vorbereiten

1. In der FRITZ!Box unter **Heimnetz → Netzwerk → Netzwerkeinstellungen** die Option **„Zugriff für Anwendungen zulassen“** aktivieren.
2. Einen eigenen FRITZ!Box-Benutzer für Netzblick anlegen: **System → FRITZ!Box-Benutzer**. Das Recht **„FRITZ!Box Einstellungen“** vergeben.

Hinweis: Die Menünamen können je nach FRITZ!OS-Version abweichen.

## Tests

```sh
cd Packages/NetzblickKit && swift test
```

## Aufbau

Die Architektur und die Designregeln stehen in [ARCHITECTURE.md](ARCHITECTURE.md).

## Lizenzen

Die Schriften Instrument Serif und Geist stehen unter der SIL Open Font License 1.1. Die Dateien liegen in `App/Resources/Fonts`.

## Marke

FRITZ! und FRITZ!Box sind Marken der FRITZ! GmbH. Netzblick ist ein unabhängiges Projekt.
