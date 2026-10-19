import SwiftUI

/// What Netzblick can and cannot see, in plain German. The wording is fixed; edit it here only.
struct LimitsView: View {

    private static let sections: [(title: String, items: [String])] = [
        (
            title: "Netzblick sieht:",
            items: [
                "alle Geräte, die deine FRITZ!Box kennt, mit Name, Hersteller und Verbindungsart",
                "wie gut dein WLAN funkt und wie schnell deine Leitung ist",
                "beim Tempo-Test: wie viel am iPhone ankommt, gemessen über Measurement Lab (M-Lab)",
                "im Lauschmodus (ab v1.1): wohin deine Geräte Anfragen schicken, nach Kategorien"
            ]
        ),
        (
            title: "Netzblick sieht nicht:",
            items: [
                "was Geräte senden oder empfangen: keine Inhalte, Nachrichten, Passwörter",
                "verschlüsselte Adress-Anfragen; die Auswertung ist darum eine Untergrenze",
                "Geräte hinter einem zweiten Router und Netze ohne FRITZ!Box",
                "was passiert, während die App geschlossen ist"
            ]
        ),
        (
            title: "Netzblick ist kein:",
            items: [
                "Virenschutz: Grün heißt „nichts Auffälliges gefunden“, nicht „sicher“",
                "Werkzeug, um andere Menschen zu überwachen; das Gastnetz bleibt außen vor"
            ]
        ),
        (
            title: "Deine Daten:",
            items: [
                "bleiben auf diesem iPhone; es gibt keinen Netzblick-Server",
                "Ausnahme Tempo-Test: M-Lab veröffentlicht jede Messung mit deiner IP-Adresse als offene Forschungsdaten; sonst schickt Netzblick nichts mit",
                "Zugangsdaten liegen im Schlüsselbund und gehen nur an deine Box",
                "Änderungen an der FRITZ!Box nur nach deiner Bestätigung"
            ]
        )
    ]

    var body: some View {
        NBCard {
            VStack(spacing: 0) {
                ForEach(Array(Self.sections.enumerated()), id: \.offset) { index, section in
                    if index > 0 {
                        NBRowDivider()
                    }
                    block(title: section.title, items: section.items)
                }
            }
        }
    }

    private func block(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title)
                .font(.nbSans(13, weight: .bold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Color.nbMuted)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "•")
                        .accessibilityHidden(true)
                    Text(verbatim: item)
                }
                .font(.nbSans(14))
                .foregroundStyle(Color.nbInkSoft)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ScrollView {
        LimitsView()
            .padding(16)
    }
    .background(Color.nbPaper)
}
