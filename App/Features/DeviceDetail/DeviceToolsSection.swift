import SwiftUI
import NetzblickKit

/// Fing-style tools for one device: ping, open services, wake up. Everything runs only on request.
struct DeviceToolsSection: View {
    let device: Device

    @Environment(AppModel.self) private var model
    @State private var ping: PingResult?
    @State private var isPinging = false
    @State private var services: [KnownService]?
    @State private var isProbing = false
    @State private var wakeMessage: String?
    @State private var isWaking = false
    @State private var confirmWake = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NBSectionTitle("Werkzeuge")

            NBCard {
                VStack(spacing: 0) {
                    toolRow(title: "Erreichbar?", result: ping?.summary, isRunning: isPinging, action: "Anpingen") {
                        isPinging = true
                        ping = await model.ping(device)
                        isPinging = false
                    }

                    NBRowDivider()

                    toolRow(title: "Offene Dienste", result: servicesSummary, isRunning: isProbing, action: "Prüfen") {
                        isProbing = true
                        services = await model.openServices(device)
                        isProbing = false
                    }

                    if let services, !services.isEmpty {
                        ForEach(services) { service in
                            serviceRow(service)
                        }
                        if services.contains(where: \.isRisky) {
                            hint("Dienste mit Warnzeichen sind alt oder unverschlüsselt. Schalte sie am Gerät ab, wenn du sie nicht brauchst.")
                        }
                        if services.contains(where: \.isCamera) {
                            hint("Das Gerät liefert einen Videostream. Ist es keine Kamera, die du kennst, sieh es dir genauer an.")
                        }
                    }

                    if model.canWakeDevices && !device.isActive && device.macAddress != nil {
                        NBRowDivider()
                        toolRow(title: "Aufwecken", result: wakeMessage, isRunning: isWaking, action: "Wecken") {
                            confirmWake = true
                        }
                    }
                }
            }
        }
        .confirmationDialog("\(device.name) aufwecken?", isPresented: $confirmWake, titleVisibility: .visible) {
            Button("Aufwecken") {
                Task {
                    isWaking = true
                    let error = await model.wakeUp(device)
                    wakeMessage = error ?? "Weckruf gesendet. Das Gerät braucht oft eine Minute."
                    isWaking = false
                }
            }
        } message: {
            Text("Die FRITZ!Box schickt einen Weckruf (Wake on LAN). Das klappt nur, wenn das Gerät es unterstützt. An den Einstellungen der Box ändert sich nichts.")
        }
    }

    private var servicesSummary: String? {
        guard let services else { return nil }
        switch services.count {
        case 0: return "keine der bekannten"
        case 1: return "1 Dienst"
        default: return "\(services.count) Dienste"
        }
    }

    private func toolRow(title: String, result: String?, isRunning: Bool, action: String,
                         perform: @escaping () async -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.nbSans(15))
                    .foregroundStyle(Color.nbInk)
                if let result {
                    Text(result)
                        .font(.nbSans(13))
                        .foregroundStyle(Color.nbMuted)
                }
            }
            Spacer(minLength: 8)
            if isRunning {
                ProgressView()
            } else {
                Button(action) {
                    Task { await perform() }
                }
                .font(.nbSans(14, weight: .semibold))
                .buttonStyle(.borderless)
            }
        }
        .padding(16)
    }

    private func serviceRow(_ service: KnownService) -> some View {
        HStack(spacing: 8) {
            Image(systemName: service.isRisky ? "exclamationmark.triangle.fill" : (service.isCamera ? "video.fill" : "circle.fill"))
                .font(.system(size: service.isRisky || service.isCamera ? 13 : 6))
                .foregroundStyle(service.isRisky ? Color.nbOrange : Color.nbMuted)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(service.name)
                .font(.nbSans(14))
                .foregroundStyle(Color.nbInkSoft)
            Spacer(minLength: 8)
            Text("Port \(service.port)")
                .font(.nbSans(12))
                .foregroundStyle(Color.nbMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.nbSans(12))
            .foregroundStyle(Color.nbMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
