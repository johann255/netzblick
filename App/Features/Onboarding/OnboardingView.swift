import Foundation
import SwiftUI

/// Three-step onboarding: welcome, a short note on the FRITZ!Box settings, and the login form.
/// The login itself is done by `AppModel.connect(host:username:password:)`.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.nbAccent) private var accent

    @State private var step: Step = .welcome

    @State private var host = "fritz.box"
    @State private var username = ""
    @State private var password = ""
    @State private var connecting = false
    @State private var errorText: String?

    @FocusState private var focus: Field?

    private enum Step: Equatable {
        case welcome
        case explain
        case login
    }

    private enum Field: Hashable {
        case host
        case username
        case password
    }

    var body: some View {
        NBScreen {
            header
        } content: {
            switch step {
            case .welcome:
                welcomeContent
            case .explain:
                explainContent
            case .login:
                loginContent
            }
        }
        .animation(.easeInOut, value: step)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        switch step {
        case .welcome:
            NBBlueHeader(
                title: "Dein Heimnetz,",
                italicTail: "verständlich.",
                subtitle: "Netzblick zeigt, was in deinem WLAN hängt und warum es hakt. Alles bleibt auf diesem iPhone."
            )
        case .explain:
            NBBlueHeader(title: "Zwei Dinge", italicTail: "vorab.")
        case .login:
            NBBlueHeader(title: "Mit der FRITZ!Box", italicTail: "verbinden.")
        }
    }

    // MARK: - Step 1: Welcome

    @ViewBuilder
    private var welcomeContent: some View {
        NBCard {
            VStack(spacing: 0) {
                NBRow(symbol: "list.bullet.rectangle", title: "Alle Geräte auf einen Blick")
                NBRowDivider()
                NBRow(symbol: "waveform.path.ecg", title: "Klare Antworten, wenn es langsam ist")
                NBRowDivider()
                NBRow(symbol: "lock.shield", title: "Kein Konto, kein Server, keine Werbung")
            }
        }

        VStack(spacing: 12) {
            Button("Mit FRITZ!Box verbinden") {
                step = .explain
            }
            .buttonStyle(NBPrimaryButtonStyle())

            Button("Erst mal ansehen (Demo)") {
                model.startDemo()
            }
            .buttonStyle(NBSecondaryButtonStyle())
        }
    }

    // MARK: - Step 2: Explain

    @ViewBuilder
    private var explainContent: some View {
        NBCard {
            VStack(spacing: 0) {
                numberedItem(
                    1,
                    "Netzblick fragt gleich nach dem Zugriff auf dein lokales Netzwerk. Ohne ihn findet die App deine FRITZ!Box nicht."
                )
                NBRowDivider()
                numberedItem(
                    2,
                    "In der FRITZ!Box muss „Zugriff für Anwendungen zulassen“ eingeschaltet sein (Heimnetz → Netzwerk → Netzwerkeinstellungen). Am besten legst du dafür einen eigenen FRITZ!Box-Benutzer an."
                )
            }
        }

        Text("Menünamen können je nach FRITZ!OS-Version abweichen.")
            .font(.nbSans(13))
            .foregroundStyle(Color.nbMuted)
            .padding(.horizontal, 4)

        VStack(spacing: 12) {
            Button("Weiter") {
                step = .login
            }
            .buttonStyle(NBPrimaryButtonStyle())

            plainButton("Zurück") {
                step = .welcome
            }
        }
    }

    private func numberedItem(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(verbatim: "\(number)")
                .font(.nbSerif(28))
                .foregroundStyle(accent)
                .frame(width: 24, alignment: .leading)

            Text(text)
                .font(.nbSans(16))
                .foregroundStyle(Color.nbInkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }

    // MARK: - Step 3: Login

    @ViewBuilder
    private var loginContent: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 16) {
                formField("Adresse der Box") {
                    TextField("", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.next)
                        .focused($focus, equals: .host)
                        .onSubmit { focus = .username }
                        .accessibilityLabel("Adresse der Box")
                }

                formField("Benutzername") {
                    TextField("", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focus, equals: .username)
                        .onSubmit { focus = .password }
                        .accessibilityLabel("Benutzername")
                }

                formField("Kennwort") {
                    SecureField("", text: $password)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .focused($focus, equals: .password)
                        .onSubmit { submit() }
                        .accessibilityLabel("Kennwort")
                }
            }
            .padding(16)
        }

        Text("Die Zugangsdaten bleiben im Schlüsselbund dieses iPhones und gehen nur an deine Box.")
            .font(.nbSans(13))
            .foregroundStyle(Color.nbMuted)
            .padding(.horizontal, 4)

        if let errorText {
            Text(errorText)
                .font(.nbSans(15))
                .foregroundStyle(Color.nbDanger)
                .padding(.horizontal, 4)
        }

        VStack(spacing: 12) {
            Button {
                submit()
            } label: {
                connectLabel
            }
            .buttonStyle(NBPrimaryButtonStyle())
            .disabled(!canConnect)

            plainButton("Zurück") {
                focus = nil
                step = .explain
            }
        }
    }

    @ViewBuilder
    private var connectLabel: some View {
        if connecting {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.white)
                Text("Verbinde …")
            }
        } else {
            Text("Verbinden")
        }
    }

    /// Label above a rounded input well.
    private func formField<Input: View>(_ label: String, @ViewBuilder input: () -> Input) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.nbSans(13, weight: .semibold))
                .foregroundStyle(Color.nbInkSoft)

            input()
                .font(.nbSans(16))
                .foregroundStyle(Color.nbInk)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.nbPaper)
                )
        }
    }

    // MARK: - Actions

    private var canConnect: Bool {
        !connecting
            && !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.isEmpty
            && !password.isEmpty
    }

    private func submit() {
        guard canConnect else { return }
        focus = nil
        connecting = true
        errorText = nil

        Task { @MainActor in
            defer { connecting = false }
            do {
                try await model.connect(
                    host: host.trimmingCharacters(in: .whitespaces),
                    username: username,
                    password: password
                )
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Text-only button in the accent color, with a 44 pt tap area.
    private func plainButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.nbSans(15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingView()
        .environment(AppModel())
}
