import SwiftUI
import NetzblickKit

/// Startseite: Kopfzeile mit Kennzahlen, neue Geräte, Tempo und Hinweise.
struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.nbAccent) private var accent

    let onStartSpeedTest: () -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let numberWords: [Int: String] = [
        2: "Zwei", 3: "Drei", 4: "Vier", 5: "Fünf", 6: "Sechs", 7: "Sieben",
        8: "Acht", 9: "Neun", 10: "Zehn", 11: "Elf", 12: "Zwölf"
    ]

    var body: some View {
        NBScreen {
            headerView
        } content: {
            if let error = model.errorMessage {
                errorBanner(error)
            }

            if model.isDemo {
                NBChip("Demo-Daten", style: .tip)
            }

            ForEach(newDeviceIDs, id: \.self) { id in
                if let device = model.device(id: id) {
                    newDeviceCard(device)
                }
            }

            NBSectionTitle("Tempo")
            tempoCard

            NBSectionTitle("Hinweise")
            findingsCard
        }
        .refreshable { await model.refresh() }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(eyebrow)
                .font(.nbSans(14, weight: .medium))
                .foregroundStyle(Color.nbOnBlueMuted)

            headline
                .foregroundStyle(.white)

            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(height: 1)
                .padding(.vertical, 4)

            HStack(alignment: .top, spacing: 12) {
                statItem(value: "\(activeDeviceCount)", label: "Geräte online")
                statItem(value: "\(model.newDeviceIDs.count)", label: "neu")
                statItem(value: wlanWord, label: "WLAN")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 24)
        // Bottom space is where the content card stack overlaps the header.
        .padding(.bottom, 76)
        .background(accent)
    }

    private var eyebrow: String {
        let date = Date().formatted(
            Date.FormatStyle()
                .weekday(.wide)
                .day()
                .month(.wide)
                .locale(Locale(identifier: "de_DE"))
        )
        let connection = model.isDemo ? "Demo-Modus" : "FRITZ!Box verbunden"
        return "\(date) · \(connection)"
    }

    private var headline: Text {
        let parts = headlineParts
        return Text(parts.head).font(.nbSerif(46))
            + Text(" " + parts.tail).font(.nbSerif(46, italic: true))
    }

    private var headlineParts: (head: String, tail: String) {
        let count = model.findings.count
        if count == 0 {
            return ("Alles läuft", "ruhig.")
        }
        if count == 1 {
            return ("Ein Ding solltest du dir", "ansehen.")
        }
        let number = Self.numberWords[count] ?? "\(count)"
        return ("\(number) Dinge solltest du dir", "ansehen.")
    }

    private var activeDeviceCount: Int {
        model.snapshot?.activeDevices.count ?? 0
    }

    private var wlanWord: String {
        let hasWifiProblem = model.findings.contains { $0.kind == .weakSignal || $0.kind == .slowBand }
        return hasWifiProblem ? "mäßig" : "gut"
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.nbSerif(40))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.nbSans(13))
                .foregroundStyle(Color.nbOnBlueMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Fehler

    private func errorBanner(_ message: String) -> some View {
        NBCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.nbWarn)
                    Text(message)
                        .font(.nbSans(15))
                        .foregroundStyle(Color.nbInkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await model.refresh() }
                } label: {
                    Text("Erneut versuchen").frame(maxWidth: .infinity)
                }
                .buttonStyle(NBSecondaryButtonStyle())
            }
            .padding(16)
        }
    }

    // MARK: - Neu im Netz

    /// At most two new devices are shown at once. Sorted, so the order is stable.
    private var newDeviceIDs: [String] {
        Array(model.newDeviceIDs.sorted().prefix(2))
    }

    private func newDeviceCard(_ device: Device) -> some View {
        NBCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("NEU IM NETZ")
                    .font(.nbSans(12, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.nbWarn)

                Text(device.name)
                    .font(.nbSerif(30))
                    .foregroundStyle(Color.nbInk)

                Text(vendorText(for: device))
                    .font(.nbSans(15))
                    .foregroundStyle(Color.nbInkSoft)

                HStack(spacing: 10) {
                    Button {
                        model.acknowledge(deviceID: device.id)
                    } label: {
                        Text("Kenne ich").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NBSecondaryButtonStyle())

                    NavigationLink {
                        DeviceDetailView(deviceID: device.id)
                    } label: {
                        Text("Genauer ansehen").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NBPrimaryButtonStyle())
                }
            }
            .padding(16)
        }
    }

    private func vendorText(for device: Device) -> String {
        if let vendor = device.vendor, !vendor.isEmpty {
            return "Hersteller: \(vendor)."
        }
        return "Hersteller unbekannt. Viele Handys nutzen private Adressen, das ist normal."
    }

    // MARK: - Tempo

    private var tempoCard: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 14) {
                if let speed = model.lastSpeed {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(speed.downloadMbps))")
                            .font(.nbSerif(44))
                            .foregroundStyle(Color.nbInk)
                        Text("Mbit/s")
                            .font(.nbSans(16))
                            .foregroundStyle(Color.nbMuted)
                    }

                    if let rating = model.lastSpeedRating {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(speedColor(rating.level))
                                .frame(width: 8, height: 8)
                            Text(rating.level.label)
                                .font(.nbSans(15, weight: .semibold))
                                .foregroundStyle(speedColor(rating.level))
                        }

                        Text(rating.explanation)
                            .font(.nbSans(15))
                            .foregroundStyle(Color.nbInkSoft)
                    }

                    Text("Gemessen \(Self.relativeFormatter.localizedString(for: speed.measuredAt, relativeTo: Date()))")
                        .font(.nbSans(13))
                        .foregroundStyle(Color.nbMuted)
                } else {
                    Text("Noch nicht gemessen. Der Test dauert etwa 8 Sekunden.")
                        .font(.nbSans(15))
                        .foregroundStyle(Color.nbInkSoft)
                }

                Button {
                    onStartSpeedTest()
                } label: {
                    Text("Tempo messen").frame(maxWidth: .infinity)
                }
                .buttonStyle(NBPrimaryButtonStyle())
            }
            .padding(16)
        }
    }

    private func speedColor(_ level: SpeedLevel) -> Color {
        switch level {
        case .slow: return .nbSpeedSlow
        case .ok: return .nbSpeedOk
        case .fast: return .nbSpeedFast
        }
    }

    // MARK: - Hinweise

    private var shownFindings: [Finding] {
        Array(model.findings.prefix(3))
    }

    @ViewBuilder
    private var findingsCard: some View {
        if model.findings.isEmpty {
            NBCard {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.nbSpeedFast)
                    Text("Keine Hinweise. Dein Netz läuft unauffällig.")
                        .font(.nbSans(15))
                        .foregroundStyle(Color.nbInk)
                }
                .padding(16)
            }
        } else {
            NBCard {
                VStack(spacing: 0) {
                    ForEach(shownFindings) { finding in
                        findingRow(finding)
                        if finding.id != shownFindings.last?.id {
                            NBRowDivider()
                        }
                    }
                }
            }
        }
    }

    private func findingRow(_ finding: Finding) -> some View {
        NavigationLink {
            FindingDetailView(finding: finding)
        } label: {
            HStack(spacing: 12) {
                // Info-Hinweise bekommen einen neutralen Punkt, alles andere den Orange-Punkt.
                NBDot(finding.severity == .info ? Color.nbGray : Color.nbOrange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.title)
                        .font(.nbSans(15, weight: .semibold))
                        .foregroundStyle(Color.nbInk)
                    Text(finding.scope)
                        .font(.nbSans(13))
                        .foregroundStyle(Color.nbMuted)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.nbMuted)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        OverviewView(onStartSpeedTest: {})
    }
    .environment(AppModel())
}
