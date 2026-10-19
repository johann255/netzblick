# Fing und Fingbox in Netzblick – Plan

Stand: 19.10.2026. Ziel: alles, was Fing (App) und Fingbox/Fing Agent können, in Netzblick abbilden,
aber ohne Telemetrie, ohne Konto und ohne Netzblick-Server. Was Fing über seine Cloud löst,
löst Netzblick über die FRITZ!Box (TR-064), über das iPhone selbst oder mit mitgelieferten Tabellen.

## Grundsätze

- **Keine Cloud.** Geräteerkennung, Verlauf, Alarme und Auswertungen laufen auf dem iPhone.
  Einziger externer Kontakt bleibt der Tempo-Test (M-Lab), vorher angekündigt.
- **Die FRITZ!Box ist die Fingbox.** Sie läuft rund um die Uhr, kennt alle Geräte und führt ein
  Ereignisprotokoll. Netzblick liest das ab, statt selbst Dauerüberwachung zu simulieren.
- **v1.0 ändert nichts an der Box.** Sperren, Pausieren und Aufwecken schreiben in die Box und
  kommen frühestens in v1.1, jeweils nur nach Bestätigung im Dialog.
- **Grenzen-Text wächst mit.** Jede neue Fähigkeit bekommt ihre Zeile in `LimitsView`.

## Abbildung

Legende: ✅ vorhanden · 🔨 in Arbeit (dieser Plan, Phase 1–3) · 🕓 später · ❓ Entscheidung von Johann · ⛔ geht auf iOS nicht

| Fing / Fingbox | Netzblick | Wie, ohne Cloud | Status |
| --- | --- | --- | --- |
| Netzwerk-Scan (alle Geräte) | Geräteliste | Hostliste der FRITZ!Box | ✅ |
| Geräteerkennung (Typ, Hersteller) | Gerätetyp mit Icon | rund 40 Gerätetypen aus Name (z. B. „MBP“ → Laptop), Bonjour und Hersteller; volle IEEE-OUI-Liste mitliefern | ✅ / 🕓 volle Liste |
| Geräteerkennung (Modell, Betriebssystem) | Modellangabe | Bonjour `_device-info._tcp` (TXT `model=`), HTTP-Titel; SSDP braucht Multicast-Berechtigung | 🕓 |
| Neue Geräte melden („Eindringling“) | „Neu“-Markierung | Vergleich mit bekannten Geräten | ✅ |
| Benachrichtigung bei neuem Gerät | Wachhund | Hintergrundabruf (`BGAppRefreshTask`) + lokale Mitteilung. iOS bestimmt den Takt, also kein Echtzeit-Alarm | 🔨 Phase 2 |
| Netzwerk-Ereignisse, Verlauf | Geräteverlauf | Online/Offline aus jedem Abruf, lokal 30 Tage | 🔨 Phase 2 |
| Digitale Anwesenheit („wer ist zuhause“) | Zuletzt gesehen | aus dem Geräteverlauf; nur eigene Geräte, nie Gastnetz | 🔨 Phase 2 |
| Router-Sicherheit, offene Ports | Sicherheits-Check | Fernzugriff, MyFRITZ!, Portfreigaben, WLAN-Verschlüsselung, WPS direkt aus der Box lesen statt von außen scannen | 🔨 Phase 1 |
| Router-Schwachstellen | Firmware-Hinweis | Update-Status der Box | ✅ |
| Ping, Erreichbarkeit | Werkzeuge im Gerätedetail | ICMP über Datagramm-Socket (ohne Root erlaubt) | 🔨 Phase 3 |
| Port-Scan eines Geräts | „Offene Dienste“ | TCP-Verbindungsversuche auf eine kurze Liste bekannter Ports | 🔨 Phase 3 |
| Versteckte Kameras finden | Kamera-Suche | Hersteller-Tabelle + offene Kamera-Ports (RTSP 554, ONVIF 8000/8899) | 🔨 Phase 3 |
| Wake on LAN | Gerät aufwecken | Über die Box (`Hosts:1#X_AVM-DE_WakeOnLANByMACAddress`), kein Broadcast nötig. Schreibt nichts um, löst nur ein Paket aus | 🔨 Phase 3 (❓ zählt das als „Änderung an der Box“?) |
| DNS-Abfrage, Traceroute | Werkzeuge | `getaddrinfo`; Traceroute über ICMP mit TTL | 🕓 |
| Bonjour/UPnP/NetBIOS-Browser | Dienste im Gerätedetail | Bonjour ist da; UPnP/SSDP braucht Multicast-Berechtigung von Apple | 🕓 |
| Speedtest | Tempo-Test | M-Lab ndt7 | ✅ |
| Speedtest-Verlauf, Provider-Bewertung | Tempo-Verlauf | alle Messungen lokal, Vergleich mit Tarif | 🕓 |
| Internet-Ausfälle | Ausfall-Verlauf | Ereignisprotokoll der Box (`DeviceInfo:1#GetDeviceLog`) auswerten | 🕓 (DSL-Werte macht der Mac-Thread) |
| ISP-Ausfallkarte (Community) | – | braucht Daten anderer Nutzer, also Telemetrie | ⛔ bewusst nicht |
| Bandbreite pro Gerät | Wer verbraucht was | Mitschnitt der Box, Bytes pro Gerät zählen | 🕓 (baut auf Lauschmodus auf) |
| WLAN-Sweet-Spot | WLAN-Messgang | eigenes Signal des iPhones live aus der WLAN-Liste der Box | 🕓 |
| Gerät blockieren, Internet pausieren | Sperren | `X_AVM-DE_HostFilter:1#DisallowWANAccessByIP` | ❓ v1.1, schreibt in die Box |
| Zeitpläne, Kindersicherung | Zugangsprofile | FRITZ!-Zugangsprofile; App erklärt, Box setzt um | ❓ v1.1 |
| Netz-Sperre für Unbekannte | – | FRITZ!Box: „Neue Geräte nur nach Freigabe“ erklären | 🕓 als Finding |
| 24/7-Überwachung ohne iPhone | – | iOS-App läuft nicht dauerhaft. Die Box kann selbst per Push-Mail über neue Geräte informieren; Netzblick erklärt die Einstellung | 🕓 als Finding |
| Mehrere Netzwerke | – | eine Box pro Installation | 🕓 |
| Andere Router | Basis-Modus | siehe CLAUDE.md, offene Frage 3 | ❓ |

## Reihenfolge

1. **Sicherheits-Check** (Phase 1, jetzt). Größter Nutzen, rein lesend, passt zu v1.0.
   Neue Box-Lesungen, neue Findings, eigener Screen mit Prüfliste.
2. **Verlauf und Wachhund** (Phase 2). Geräteverlauf im Kit, Hintergrundabruf, lokale Mitteilung
   bei neuem Gerät, „zuletzt gesehen“ im Gerätedetail.
3. **Werkzeuge** (Phase 3). Ping, offene Dienste, Kamera-Suche, Wake on LAN.
4. Danach: Tempo- und Ausfall-Verlauf, volle OUI-Liste, WLAN-Messgang, Bandbreite pro Gerät.

## Was Johann entscheiden muss

- Wake on LAN über die Box schon in v1.0? Es ändert keine Einstellung, löst aber eine Aktion aus.
- Sperren und Pausieren (v1.1): mit Bestätigungsdialog, und nur für Geräte im Heimnetz.
- Mitteilungen bei neuen Geräten: an oder aus als Standard? Vorschlag: aus, beim ersten neuen Gerät fragen.

## Datenschutz pro Funktion

- Sicherheits-Check: liest Einstellungen, nie WLAN-Passwörter (`GetSecurityKeys` wird nicht aufgerufen).
- Verlauf: bleibt in der App, wird mit „Alles löschen“ entfernt, Gastnetz wird nicht protokolliert.
- Werkzeuge: sprechen nur Geräte im eigenen Heimnetz an.
- Hintergrundabruf: spricht nur mit der Box.
