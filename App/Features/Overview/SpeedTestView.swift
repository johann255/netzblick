import SwiftUI
import NetzblickKit

/// Tempo-Test als Sheet: Live-Anzeige in der Ampelfarbe, Ergebnis und Blick auf die Leitung.
struct SpeedTestView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nbAccent) private var accent

    private enum Phase: Equatable {
        case idle
        case running
        case finished
        case failed
    }

    @State private var phase: Phase = .idle
    @State private var current: Double = 0
    @State private var progress: Double = 0
    @State private var result: SpeedResult?
    @State private var task: Task<Void, Never>?
    @State private var live: LiveThroughput?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.nbInk)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.nbCard))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Schließen")
                }

                colorCard

                if phase == .finished || phase == .failed {
                    infoCard
                }

                actionButton

                liveCard

                Text("Gemessen wird über einen externen Testserver. Er sieht nur deine IP-Adresse, wie jede Webseite. Referenz: grün ab 90 % deines Tarifs (ohne Tarif ab 50 Mbit/s), rot unter 50 % (ohne Tarif unter 15 Mbit/s).")
                    .font(.nbSans(13))
                    .foregroundStyle(Color.nbMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .background(Color.nbPaper.ignoresSafeArea())
        .onDisappear { task?.cancel() }
        .task { await pollLiveThroughput() }
    }

    // MARK: - Werte und Farben

    /// The number on the card: live during the test, the final result afterwards.
    private var shownMbps: Double? {
        switch phase {
        case .idle, .failed:
            return nil
        case .running:
            return current > 0 ? current : nil
        case .finished:
            return result?.downloadMbps
        }
    }

    private var level: SpeedLevel? {
        guard let mbps = shownMbps else { return nil }
        return SpeedRating.rate(downloadMbps: mbps, bookedMbps: model.bookedDownloadMbps).level
    }

    /// Before any value exists the card shows the accent blue.
    private var fillColor: Color {
        guard let level else { return accent }
        return ratingColor(level)
    }

    /// White on red and green; dark ink on yellow for contrast.
    private var textColor: Color {
        level == .ok ? Color.nbInk : .white
    }

    /// The word is always shown, so the colour is never the only signal.
    private var statusWord: String {
        if let level { return level.label }
        return phase == .running ? "misst" : "bereit"
    }

    private var valueText: String {
        guard let mbps = shownMbps else { return "–" }
        return "\(Int(mbps))"
    }

    private func ratingColor(_ level: SpeedLevel) -> Color {
        switch level {
        case .slow: return .nbSpeedSlow
        case .ok: return .nbSpeedOk
        case .fast: return .nbSpeedFast
        }
    }

    // MARK: - Farbkarte

    private var colorCard: some View {
        VStack(spacing: 8) {
            Text("TEMPO-TEST")
                .font(.nbSans(13, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(textColor.opacity(0.85))

            Text(valueText)
                .font(.nbSerif(96))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.numericText())
                .foregroundStyle(textColor)

            Text("Mbit/s")
                .font(.nbSans(18))
                .foregroundStyle(textColor)

            Text(statusWord)
                .font(.nbSans(18, weight: .semibold))
                .foregroundStyle(textColor)

            ProgressView(value: progress)
                .tint(.white)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(fillColor)
        )
        .animation(.easeInOut(duration: 0.4), value: level)
    }

    // MARK: - Ergebnis

    @ViewBuilder
    private var infoCard: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 12) {
                if phase == .failed {
                    Text("Der Test hat nicht geklappt. Bist du mit dem Internet verbunden?")
                        .font(.nbSans(15))
                        .foregroundStyle(Color.nbInk)
                } else if let result {
                    Text(SpeedRating.rate(downloadMbps: result.downloadMbps, bookedMbps: model.bookedDownloadMbps).explanation)
                        .font(.nbSans(15))
                        .foregroundStyle(Color.nbInkSoft)

                    if let verdict = BottleneckVerdict.judge(
                        phoneMbps: result.downloadMbps,
                        lineMaxMbps: model.snapshot?.wan?.maxDownstreamMbps
                    ).sentence {
                        Text(verdict)
                            .font(.nbSans(15))
                            .foregroundStyle(Color.nbInkSoft)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Aktionen

    @ViewBuilder
    private var actionButton: some View {
        switch phase {
        case .idle:
            Button {
                start()
            } label: {
                Text("Messen starten").frame(maxWidth: .infinity)
            }
            .buttonStyle(NBPrimaryButtonStyle())

        case .running:
            Button {
                task?.cancel()
            } label: {
                Text("Abbrechen").frame(maxWidth: .infinity)
            }
            .buttonStyle(NBSecondaryButtonStyle())

        case .finished, .failed:
            Button {
                start()
            } label: {
                Text("Nochmal messen").frame(maxWidth: .infinity)
            }
            .buttonStyle(NBPrimaryButtonStyle())
        }
    }

    private func start() {
        task?.cancel()
        current = 0
        progress = 0
        result = nil
        phase = .running

        task = Task { @MainActor in
            do {
                let measured = try await model.runSpeedTest { sample in
                    Task { @MainActor in
                        current = sample.currentMbps
                        progress = sample.progress
                    }
                }
                result = measured
                phase = .finished
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed
            }
        }
    }

    // MARK: - Leitung

    private var liveCard: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Gerade über die Leitung")
                    .font(.nbSans(15, weight: .semibold))
                    .foregroundStyle(Color.nbInk)

                if let live {
                    Text("↓ \(Self.formatMbps(live.downstreamMbps)) Mbit/s   ↑ \(Self.formatMbps(live.upstreamMbps)) Mbit/s")
                        .font(.nbSans(20, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.nbInk)
                } else {
                    Text("Nicht verfügbar")
                        .font(.nbSans(17))
                        .foregroundStyle(Color.nbMuted)
                }

                Text("Das ist, was dein Haushalt gerade nutzt – nicht das Höchsttempo.")
                    .font(.nbSans(13))
                    .foregroundStyle(Color.nbMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pollLiveThroughput() async {
        while !Task.isCancelled {
            live = await model.liveThroughput()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private static func formatMbps(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "de_DE")))
    }
}

#Preview {
    SpeedTestView()
        .environment(AppModel())
}
