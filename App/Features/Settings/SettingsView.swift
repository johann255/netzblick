import SwiftUI

struct SettingsView: View {
    @AppStorage("accentBlue") private var accentRaw = AccentBlue.ultramarin.rawValue
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("bookedDownloadMbps") private var bookedText = ""
    @AppStorage(NewDeviceAlerts.enabledKey) private var notifyNewDevices = false

    @State private var confirmDelete = false

    let boxName: String?
    let onDisconnect: () -> Void
    let onDeleteAll: () -> Void

    init(boxName: String?, onDisconnect: @escaping () -> Void, onDeleteAll: @escaping () -> Void) {
        self.boxName = boxName
        self.onDisconnect = onDisconnect
        self.onDeleteAll = onDeleteAll
    }

    private var currentBlue: AccentBlue {
        AccentBlue(rawValue: accentRaw) ?? AccentBlue.standard
    }

    var body: some View {
        NBScreen {
            NBBlueHeader(
                title: "Einstellungen",
                subtitle: "Netzblick 1.0 · alles bleibt auf diesem iPhone"
            )
        } content: {
            blueCard

            Picker("Darstellung", selection: $appearance) {
                Text("Hell").tag("light")
                Text("Dunkel").tag("dark")
                Text("System").tag("system")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            NBSectionTitle("Dein Tarif")
            tariffCard

            NBSectionTitle("FRITZ!Box")
            boxCard

            NBSectionTitle("Wachhund")
            watchdogCard

            NBSectionTitle("Was Netzblick kann – und was nicht")
            LimitsView()

            NBSectionTitle("Daten & Info")
            dataCard
        }
    }

    // MARK: - Dein Blau

    private var blueCard: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Dein Blau")
                        .font(.nbSerif(26))
                        .foregroundStyle(Color.nbInk)
                    Spacer(minLength: 8)
                    Text(currentBlue.name)
                        .font(.nbSans(14))
                        .foregroundStyle(Color.nbMuted)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                    spacing: 16
                ) {
                    ForEach(AccentBlue.allCases) { blue in
                        blueButton(blue)
                    }
                }
            }
            .padding(16)
        }
    }

    private func blueButton(_ blue: AccentBlue) -> some View {
        let selected = blue == currentBlue
        return Button {
            accentRaw = blue.rawValue
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(blue.color)
                    .frame(height: 56)
                    // Gap between swatch and ring, so the selected ring shows on a same-colored fill.
                    .padding(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(selected ? blue.color : Color.nbLine, lineWidth: 2)
                    )

                Text(blue.name)
                    .font(.nbSans(13, weight: .semibold))
                    .foregroundStyle(Color.nbInk)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Tarif

    private var tariffCard: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Gebuchtes Tempo (Mbit/s, Download)", text: $bookedText)
                    .keyboardType(.numberPad)
                    .font(.nbSans(16))
                    .foregroundStyle(Color.nbInk)

                Text("Damit bewertet der Tempo-Test im Verhältnis zu deinem Tarif. Leer lassen geht auch.")
                    .font(.nbSans(13))
                    .foregroundStyle(Color.nbMuted)
            }
            .padding(16)
        }
    }

    // MARK: - FRITZ!Box

    private var boxCard: some View {
        NBCard {
            VStack(spacing: 0) {
                infoRow(title: "Verbunden mit", value: boxName ?? "Demo-Modus")
                NBRowDivider()

                Button(role: .destructive) {
                    onDisconnect()
                } label: {
                    Text("Verbindung trennen")
                        .font(.nbSans(16, weight: .semibold))
                        .foregroundStyle(Color.nbDanger)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Wachhund

    private var watchdogCard: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { notifyNewDevices },
                    set: { wanted in
                        guard wanted else {
                            notifyNewDevices = false
                            NewDeviceAlerts.schedule()
                            return
                        }
                        Task {
                            notifyNewDevices = await NewDeviceAlerts.requestPermission()
                            NewDeviceAlerts.schedule()
                        }
                    }
                )) {
                    Text("Bei neuen Geräten melden")
                        .font(.nbSans(16))
                        .foregroundStyle(Color.nbInk)
                }

                Text("Netzblick fragt ab und zu im Hintergrund die FRITZ!Box und meldet Geräte, die du noch nicht kennst. Wie oft, entscheidet iOS. Nur im Heim-WLAN, nichts verlässt dein iPhone.")
                    .font(.nbSans(13))
                    .foregroundStyle(Color.nbMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }

    // MARK: - Daten & Info

    private var dataCard: some View {
        NBCard {
            VStack(spacing: 0) {
                infoRow(title: "Geräteprofile", value: "Stand Oktober 2026")
                NBRowDivider()

                Link("Datenschutzerklärung", destination: URL(string: "https://johann255.github.io/netzblick/datenschutz")!)
                    .font(.nbSans(16))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                NBRowDivider()

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Text("Alle Daten auf diesem iPhone löschen")
                        .font(.nbSans(16, weight: .semibold))
                        .foregroundStyle(Color.nbDanger)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .confirmationDialog(
                    "Alle Daten auf diesem iPhone löschen?",
                    isPresented: $confirmDelete,
                    titleVisibility: .visible
                ) {
                    Button("Alle Daten löschen", role: .destructive) {
                        onDeleteAll()
                    }
                    Button("Abbrechen", role: .cancel) {}
                } message: {
                    Text("Das lässt sich nicht rückgängig machen.")
                }
            }
        }
    }

    // MARK: - Helpers

    private func infoRow(title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.nbSans(16))
                .foregroundStyle(Color.nbInk)
            Spacer(minLength: 8)
            Text(value)
                .font(.nbSans(16))
                .foregroundStyle(Color.nbMuted)
        }
        .padding(16)
    }
}

#Preview {
    SettingsView(boxName: "FRITZ!Box 7590 AX", onDisconnect: {}, onDeleteAll: {})
}
