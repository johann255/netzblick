import SwiftUI
import NetzblickKit

/// Wi-Fi walk as a sheet: live signal of this iPhone as the FRITZ!Box sees it, one tap per room,
/// and a small map of the home with the best place for a repeater.
struct SignalWalkView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nbAccent) private var accent

    @State private var link: WiFiLink?
    @State private var hasAnswer = false
    @State private var customRoom = ""
    @State private var lastNoted: String?

    private var walk: SignalWalk { model.signalWalk }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                Text("Geh mit dem iPhone durch die Wohnung und tipp in jedem Raum auf seinen Namen. Mehrmals tippen macht den Wert genauer.")
                    .font(.nbSans(15))
                    .foregroundStyle(Color.nbInkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                liveCard
                roomButtons

                if !walk.spots.isEmpty {
                    NBSectionTitle("Deine Wohnung")
                    mapCard
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

    // MARK: - Header

    private var header: some View {
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
    }

    // MARK: - Live

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

    // MARK: - Room buttons

    private var canNote: Bool { link?.signalPercent != nil }

    private var roomButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ich bin gerade im …")
                .font(.nbSans(13, weight: .semibold))
                .foregroundStyle(Color.nbMuted)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(roomChoices, id: \.self) { name in
                    roomButton(name)
                }
            }

            HStack(spacing: 8) {
                TextField("Anderer Raum", text: $customRoom)
                    .font(.nbSans(15))
                    .foregroundStyle(Color.nbInk)
                    .submitLabel(.done)
                    .onSubmit { note(customRoom) }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.nbCard))
                Button("Merken") { note(customRoom) }
                    .font(.nbSans(15, weight: .semibold))
                    .disabled(!canNote || customRoom.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// Suggested rooms plus any custom ones already noted.
    private var roomChoices: [String] {
        let custom = walk.spots.map(\.name).filter { name in
            !SignalWalk.suggestedRooms.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
        return SignalWalk.suggestedRooms + custom
    }

    private func roomButton(_ name: String) -> some View {
        let spot = walk.spots.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        let justNoted = lastNoted == name

        return Button {
            note(name)
        } label: {
            VStack(spacing: 2) {
                Text(name)
                    .font(.nbSans(14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(spot?.signalPercent.map { "\($0) %" } ?? " ")
                    .font(.nbSans(12))
                    .monospacedDigit()
            }
            .foregroundStyle(spot.map { textColor($0.quality) } ?? Color.nbInk)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(spot.map { color($0.quality) } ?? Color.nbCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(justNoted ? accent : Color.nbLine, lineWidth: justNoted ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canNote)
        .sensoryFeedback(.success, trigger: spot?.samples.count ?? 0)
        .accessibilityLabel(name + (spot?.signalPercent.map { ", \($0) Prozent" } ?? ""))
        .accessibilityHint("Merkt das aktuelle Signal für diesen Raum")
    }

    private func note(_ name: String) {
        guard let link, link.signalPercent != nil else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.noteRoom(trimmed, link: link)
        lastNoted = trimmed
        if trimmed == customRoom.trimmingCharacters(in: .whitespacesAndNewlines) { customRoom = "" }
    }

    // MARK: - Mini map

    private var mapCard: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(walk.floors, id: \.floor) { floor in
                    VStack(alignment: .leading, spacing: 8) {
                        if walk.floors.count > 1 {
                            Text(floor.floor.title)
                                .font(.nbSans(12, weight: .bold))
                                .tracking(1)
                                .textCase(.uppercase)
                                .foregroundStyle(Color.nbMuted)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
                            ForEach(floor.spots.sorted { ($0.signalPercent ?? 0) > ($1.signalPercent ?? 0) }) { spot in
                                roomTile(spot)
                            }
                        }
                    }
                }

                legend

                if let verdict = walk.verdict {
                    Text(verdict)
                        .font(.nbSans(14))
                        .foregroundStyle(Color.nbInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(role: .destructive) {
                    model.resetWalk()
                    lastNoted = nil
                } label: {
                    Text("Neu beginnen")
                        .font(.nbSans(14, weight: .semibold))
                }
                .buttonStyle(.borderless)
            }
            .padding(16)
        }
    }

    private func roomTile(_ spot: SignalSpot) -> some View {
        let isBox = spot.id == walk.boxRoom?.id
        let isRepeater = spot.id == walk.repeaterRoom?.id

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(spot.name)
                    .font(.nbSans(13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isBox {
                    Image(systemName: "wifi.router")
                        .accessibilityLabel("FRITZ!Box vermutlich hier")
                }
                if isRepeater {
                    Image(systemName: "plus.circle.fill")
                        .accessibilityLabel("Repeater hierhin")
                }
            }
            Text(spot.signalPercent.map { "\($0) %" } ?? "–")
                .font(.nbSerif(24))
                .monospacedDigit()
            Text(spot.rateMbps.map { "\($0) Mbit/s" } ?? " ")
                .font(.nbSans(11))
                .monospacedDigit()
        }
        .foregroundStyle(textColor(spot.quality))
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color(spot.quality)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isRepeater ? Color.nbInk : Color.clear, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
        )
        .contextMenu {
            Button(role: .destructive) {
                model.removeRoom(id: spot.id)
            } label: {
                Label("Raum entfernen", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            Label("Box vermutlich hier", systemImage: "wifi.router")
            if walk.repeaterRoom != nil {
                Label("Repeater hierhin", systemImage: "plus.circle.fill")
            }
        }
        .font(.nbSans(12))
        .foregroundStyle(Color.nbMuted)
    }

    /// Yellow is too light for white text.
    private func textColor(_ quality: SignalQuality) -> Color {
        quality == .fair ? Color.black.opacity(0.85) : Color.white
    }

    private func color(_ quality: SignalQuality) -> Color {
        switch quality {
        case .strong: return .nbSpeedFast
        case .fair: return .nbSpeedOk
        case .weak: return .nbSpeedSlow
        case .unknown: return .nbGray
        }
    }
}

#Preview {
    SignalWalkView()
        .environment(AppModel())
}
