import SwiftUI
import NetzblickKit

/// Explains why Wi-Fi is slow: line speed, the iPhone measurement and the ranked findings.
struct DiagnosisView: View {
    let onStartSpeedTest: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.nbAccent) private var accent

    var body: some View {
        NBScreen {
            NBBlueHeader(
                eyebrow: eyebrow,
                title: "Warum ist das WLAN",
                italicTail: "langsam?"
            )
        } content: {
            lineCard

            ForEach(Array(model.speedFindings.enumerated()), id: \.element.id) { index, finding in
                findingCard(finding, rank: index + 1)
            }

            if model.snapshot != nil && model.speedFindings.isEmpty {
                nothingFoundCard
            }

            Button {
                Task { await model.refresh() }
            } label: {
                Text("Erneut prüfen")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NBSecondaryButtonStyle())
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await model.refresh() }
    }

    // MARK: - Header

    private var eyebrow: String {
        guard let takenAt = model.snapshot?.takenAt else { return "Diagnose" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .full
        return "Diagnose · geprüft " + formatter.localizedString(for: takenAt, relativeTo: Date())
    }

    // MARK: - Leitung

    private var lineCard: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Deine Internetleitung")
                    .font(.nbSerif(26))
                    .foregroundStyle(Color.nbInk)

                lineStatus

                if let speed = model.lastSpeed {
                    measuredPart(speed)
                }

                Button {
                    onStartSpeedTest()
                } label: {
                    Text("Tempo messen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NBSecondaryButtonStyle())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var lineStatus: some View {
        if let wan = model.snapshot?.wan {
            if !wan.isUp {
                Text("Die Verbindung ins Internet ist gerade getrennt.")
                    .font(.nbSans(14, weight: .semibold))
                    .foregroundStyle(Color.nbWarn)
            }

            if let line = wan.maxDownstreamMbps {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(line.rounded()))")
                            .font(.nbSerif(30))
                            .foregroundStyle(Color.nbInk)
                        Text("Mbit/s")
                            .font(.nbSans(16))
                            .foregroundStyle(Color.nbMuted)
                    }
                    Text("So schnell ist die Leitung zur FRITZ!Box synchronisiert.")
                        .font(.nbSans(14))
                        .foregroundStyle(Color.nbMuted)
                }
            }
        } else {
            Text("Keine Angaben zur Leitung von der FRITZ!Box.")
                .font(.nbSans(14))
                .foregroundStyle(Color.nbMuted)
        }
    }

    private func measuredPart(_ speed: SpeedResult) -> some View {
        let line = model.snapshot?.wan?.maxDownstreamMbps
        let verdict = BottleneckVerdict.judge(phoneMbps: speed.downloadMbps, lineMaxMbps: line)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Am iPhone gemessen: \(Int(speed.downloadMbps.rounded())) Mbit/s")
                .font(.nbSans(15, weight: .semibold))
                .foregroundStyle(Color.nbInk)

            if let line, line > 0 {
                let share = min(speed.downloadMbps / line, 1)
                NBSegmentBar(
                    segments: [
                        (value: share, color: accent),
                        (value: 1 - share, color: Color.nbLine)
                    ],
                    accessibilityLabel: "\(Int((share * 100).rounded())) Prozent der Leitungsgeschwindigkeit"
                )
            }

            if let sentence = verdict.sentence {
                Text(sentence)
                    .font(.nbSans(14))
                    .foregroundStyle(Color.nbInkSoft)
            }
        }
    }

    // MARK: - Findings

    private func findingCard(_ finding: Finding, rank: Int) -> some View {
        let isTop = finding.severity == .high

        return NBCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text("\(rank)")
                        .font(.nbSerif(40))
                        .foregroundStyle(accent)
                    Spacer(minLength: 8)
                    NBChip(
                        isTop ? "Größter Effekt" : finding.scope,
                        style: isTop ? .warn : .tip
                    )
                }

                Text(finding.title)
                    .font(.nbSerif(26))
                    .foregroundStyle(Color.nbInk)

                Text(finding.explanation)
                    .font(.nbSans(14))
                    .foregroundStyle(Color.nbInkSoft)

                NavigationLink {
                    FindingDetailView(finding: finding)
                } label: {
                    Text("So stellst du es ein")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NBPrimaryButtonStyle())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var nothingFoundCard: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nichts gefunden")
                    .font(.nbSerif(26))
                    .foregroundStyle(Color.nbInk)

                Text("Dein WLAN sieht gut aus. Wenn es trotzdem hakt, miss das Tempo direkt am betroffenen Ort.")
                    .font(.nbSans(14))
                    .foregroundStyle(Color.nbInkSoft)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    NavigationStack {
        DiagnosisView(onStartSpeedTest: {})
    }
    .environment(AppModel())
}
