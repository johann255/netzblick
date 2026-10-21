import SwiftUI
import NetzblickKit

/// Security check of the home network: a checklist of what was looked at, then the findings with steps.
/// Read-only; every change is made by the user in the FRITZ!Box.
struct SecurityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NBScreen {
            NBBlueHeader(
                eyebrow: "Sicherheits-Check",
                title: "Wie dicht ist",
                italicTail: "dein Netz?",
                subtitle: subtitle
            )
        } content: {
            NBCard {
                VStack(spacing: 0) {
                    ForEach(model.securityChecks) { item in
                        checkRow(item)
                        if item.id != model.securityChecks.last?.id {
                            NBRowDivider()
                        }
                    }
                }
            }

            if !model.securityFindings.isEmpty {
                NBSectionTitle("Was du tun kannst")
                ForEach(model.securityFindings) { finding in
                    findingCard(finding)
                }
            }

            Text("Netzblick liest diese Einstellungen nur aus der FRITZ!Box. Das WLAN-Passwort liest es nie. Grün heißt „nichts Auffälliges“, nicht „sicher“.")
                .font(.nbSans(13))
                .foregroundStyle(Color.nbMuted)
                .padding(.horizontal, 4)
        }
        .refreshable { await model.refresh() }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var subtitle: String {
        let warnings = model.securityChecks.filter { $0.state == .warn }.count
        switch warnings {
        case 0: return "Nichts Auffälliges gefunden."
        case 1: return "Ein Punkt verdient einen Blick."
        default: return "\(warnings) Punkte verdienen einen Blick."
        }
    }

    private func checkRow(_ item: SecurityCheckItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol(item.state))
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(color(item.state))
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(item.title)
                .font(.nbSans(15, weight: .semibold))
                .foregroundStyle(Color.nbInk)
            Spacer(minLength: 8)
            Text(item.detail)
                .font(.nbSans(14))
                .foregroundStyle(item.state == .warn ? Color.nbWarn : Color.nbMuted)
                .multilineTextAlignment(.trailing)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ state: SecurityCheckItem.State) -> String {
        switch state {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func color(_ state: SecurityCheckItem.State) -> Color {
        switch state {
        case .ok: return .nbSpeedFast
        case .warn: return .nbOrange
        case .unknown: return .nbGray
        }
    }

    private func findingCard(_ finding: Finding) -> some View {
        NBCard {
            VStack(alignment: .leading, spacing: 12) {
                NBChip(finding.severity == .high ? "Wichtig" : finding.scope, style: finding.severity == .high ? .warn : .tip)
                Text(finding.title)
                    .font(.nbSerif(26))
                    .foregroundStyle(Color.nbInk)
                Text(finding.explanation)
                    .font(.nbSans(14))
                    .foregroundStyle(Color.nbInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
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
}

#Preview {
    NavigationStack {
        SecurityView()
    }
    .environment(AppModel())
}
