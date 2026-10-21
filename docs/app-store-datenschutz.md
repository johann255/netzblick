# App-Store-Datenschutzangaben – Entwurf

Stand: 21.10.2026. Entwurf für App Store Connect („App-Datenschutz“), das Privacy Manifest
(`App/PrivacyInfo.xcprivacy`) und die Datenschutzerklärung. Muss zum Verhalten der App passen;
bei jeder neuen Funktion mit externem Kontakt hier nachziehen.

## Grundlage: Was verlässt das iPhone?

| Weg | Empfänger | Was | Wann |
| --- | --- | --- | --- |
| TR-064, Web-Oberfläche der Box | eigene FRITZ!Box im Heimnetz | Anmeldedaten, Abfragen | bei jedem Abruf, Lauschmodus, Werkzeugen |
| Ping, offene Dienste | Geräte im eigenen Heimnetz | ICMP-Echo, TCP-Verbindungsaufbau ohne Inhalt | nur auf Knopfdruck |
| Tempo-Test | Measurement Lab (M-Lab), Locate-API und ein ndt7-Server | IP-Adresse, Messwerte (Tempo, Laufzeit, TCP-Statistik). Kein Gerätename, keine Version, User-Agent „ndt7“ | nur auf Knopfdruck, nach Hinweis |

Daten an die eigene FRITZ!Box und an Geräte im eigenen Heimnetz gelten nicht als „erhoben“: Sie
gehen nicht an den Entwickler und nicht an Dritte. Es gibt keinen Netzblick-Server, kein Analytics,
kein Crash-SDK, keine Werbung.

**M-Lab zählt als Dritter**, weil es die Messung mit IP-Adresse dauerhaft speichert und als offene
Forschungsdaten veröffentlicht (https://www.measurementlab.net/privacy/). Apple fragt nach Daten,
die „du oder deine Drittanbieter-Partner“ länger als für die Anfrage nötig speichern. Das trifft zu.

## Antworten in App Store Connect

**Erfasst diese App Daten?** Ja.

| Datentyp (Apple) | Erfasst | Mit Identität verknüpft | Tracking | Zweck |
| --- | --- | --- | --- | --- |
| Diagnose → Leistungsdaten | ja (Tempo-Test bei M-Lab) | nein | nein | App-Funktionalität |
| Standort → Ungefährer Standort | ja, vorsichtshalber: M-Lab ordnet die IP-Adresse einem Ort zu und veröffentlicht ihn | nein | nein | App-Funktionalität |

Alle anderen Kategorien (Kontaktdaten, Gesundheit, Finanzen, genauer Standort, Kontakte,
Nutzerinhalte, Verlauf, Kennungen, Käufe, Nutzungsdaten, sonstige Daten): **nicht erfasst**.

Begründung „nicht verknüpft“: Netzblick hat kein Konto und sendet keine Kennung; M-Lab erhält nur
IP-Adresse und Messung. Begründung „kein Tracking“: keine Verknüpfung mit Daten anderer Firmen,
keine Werbung, keine Weitergabe an Datenhändler.

**Offen, vor dem Einreichen prüfen:**
- Ob Apple die IP-Adresse allein als „Ungefährer Standort“ erwartet. Der Standort wird von M-Lab
  abgeleitet, nicht von Netzblick. Lieber angeben als fehlen lassen; im Zweifel beim App-Review-Team nachfragen.
- Ob „Leistungsdaten“ oder „Sonstige Diagnosedaten“ besser passt. Vorschlag: Leistungsdaten.

## Privacy Manifest

`App/PrivacyInfo.xcprivacy` spiegelt die Tabelle oben:
- `NSPrivacyTracking`: false, keine Tracking-Domains.
- `NSPrivacyCollectedDataTypes`: `PerformanceData` und `CoarseLocation`, jeweils nicht verknüpft,
  kein Tracking, Zweck `AppFunctionality`.
- `NSPrivacyAccessedAPITypes`: UserDefaults mit CA92.1 (eigene Einstellungen) und 1C8F.1
  (Akzentfarbe über die App Group). Weitere „Required Reason“-APIs nutzt die App derzeit nicht
  (keine Dateizeitstempel, kein Systemstart, kein freier Speicher).

Die Widget-Erweiterung (`Widgets/PrivacyInfo.xcprivacy`) erhebt nichts; sie liest die Akzentfarbe aus
der App Group und hat darum dieselben zwei UserDefaults-Gründe.

## Datenschutzerklärung (Entwurf für johann255.github.io/netzblick/datenschutz)

> **Netzblick – Datenschutz**
>
> Netzblick läuft vollständig auf deinem iPhone. Es gibt keinen Netzblick-Server, kein Konto,
> keine Werbung und keine Auswertung deiner Nutzung.
>
> **FRITZ!Box.** Netzblick spricht im Heimnetz mit deiner FRITZ!Box und liest Geräteliste,
> WLAN-Zustand, Leitungstempo und Sicherheitseinstellungen. Dein WLAN-Passwort liest Netzblick nie.
> Benutzername und Kennwort der Box liegen im Schlüsselbund dieses iPhones und gehen nur an deine Box.
>
> **Gespeichert auf dem iPhone.** Bekannte Geräte, der Verlauf, wann welches Gerät online war
> (30 Tage, ohne Gastnetz), die letzten Tempo-Messungen und die Auswertung des Lauschmodus.
> „Alles löschen“ in den Einstellungen entfernt alles.
>
> **Tempo-Test.** Nur wenn du ihn startest, misst Netzblick über Measurement Lab (M-Lab), ein
> offenes Forschungsprojekt. M-Lab speichert jede Messung mit deiner IP-Adresse und veröffentlicht
> sie als offene Daten; aus der IP-Adresse lässt sich ungefähr ablesen, wo du bist.
> Netzblick schickt keinen Namen, keine Gerätekennung und keine App-Version mit.
> Datenschutz bei M-Lab: https://www.measurementlab.net/privacy/
>
> **Werkzeuge und Wachhund.** Ping und die Prüfung offener Dienste sprechen nur Geräte in deinem
> Heimnetz an. Der Wachhund (standardmäßig aus) fragt im Hintergrund nur deine FRITZ!Box.
> Mitteilungen entstehen auf dem iPhone.
>
> **Kontakt.** Johann Neubert, johann.neubert@posteo.de

Vor Veröffentlichung: ladungsfähige Anschrift für das Impressum ergänzen (Pflicht in Deutschland).
