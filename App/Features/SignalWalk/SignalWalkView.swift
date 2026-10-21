import SwiftUI
import NetzblickKit

/// Wi-Fi walk as a sheet: live signal of this iPhone as the FRITZ!Box sees it, and a note per room.
struct SignalWalkView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nbAccent) private var accent

    @State private var link: WiFiLink?
    @State private var hasAnswer = false
    @State private var room = ""
    @State private var walk = SignalWalk()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("WLAN-Messgang")
                        .font(.nbSerif(32))
                        .foregroundStyle(Color.nbInk)
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

                Text("Geh mit dem iPhone durch die Wohnung. Netzblick zeigt, wie stark die FRITZ!Box dich gerade empfängt. Merk dir jeden Raum mit einem Tipp.")
                    .font(.nbSans(15))
                    .foregroundStyle(Color.nbInkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                liveCard
                noteCard

                if !walk.spots.isEmpty {
                    spotsCard
                }
            }
            .padding(16)
        }
        .background(Color.nbPaper.ignoresSafeArea())
        .task {
            // Polls while the sheet is open; stops by itself when it closes.
            while !Task.isCancelled {
                link = await model.ownWiFiLink()
                hasAnswer = true
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var liveCard: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 8) {
                if let link, let signal = link.signalPercent {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(signal)")
                            .font(.nbSerif(64))
                            .foregroundStyle(Color.nbInk)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("%")
                            .font(.nbSans(18))
                            .foregroundStyle(Color.nbMuted)
                        Spacer()
                        Text(link.quality.label)
                            .font(.nbSans(15, weight: .semibold))
                            .foregroundStyle(color(link.quality))
                    }
                    ProgressView(value: Double(signal), total: 100)
                        .tint(color(link.quality))
                    Text("WLAN \(link.band.label)" + (link.rateMbps.map { " · \($0) Mbit/s Verbindung" } ?? ""))
                        .font(.nbSans(13))
                        .foregroundStyle(Color.nbMuted)
                } else if hasAnswer {
                    Text("Die FRITZ!Box meldet für dieses iPhone gerade kein WLAN-Signal. Bist du im Heim-WLAN?")
                        .font(.nbSans(15))
                        .foregroundStyle(Color.nbInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.default, value: link)
        }
    }

    private var noteCard: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Raum, z. B. Küche", text: $room)
                    .font(.nbSans(16))
                    .foregroundStyle(Color.nbInk)
                    .submitLabel(.done)
                    .onSubmit(noteRoom)
                Button(action: noteRoom) {
                    Text("Hier merken")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NBPrimaryButtonStyle())
                .disabled(link?.signalPercent == nil)
            }
            .padding(16)
        }
    }

    private var spotsCard: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(walk.ranked) { spot in
                    HStack(spacing: 12) {
                        Text(spot.name)
                            .font(.nbSans(15))
                            .foregroundStyle(Color.nbInk)
                        Spacer(minLength: 8)
                        Text(spot.link.signalPercent.map { "\($0) %" } ?? "–")
                            .font(.nbSans(15, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(color(spot.link.quality))
                    }
                    .padding(16)
                    NBRowDivider()
                }
                if let verdict = walk.verdict {
                    Text(verdict)
                        .font(.nbSans(14))
                        .foregroundStyle(Color.nbInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                }
            }
        }
    }

    private func noteRoom() {
        guard let link, link.signalPercent != nil else { return }
        walk.note(room, link: link)
        room = ""
    }

    private func color(_ quality: SignalQuality) -> Color {
        switch quality {
        case .strong: return .nbSpeedFast
        case .fair: return .nbSpeedOk
        case .weak: return .nbSpeedSlow
        case .unknown: return .nbMuted
        }
    }
}

#Preview {
    SignalWalkView()
        .environment(AppModel())
}
