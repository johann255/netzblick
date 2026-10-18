import SwiftUI
import NetzblickKit

@main
struct NetzblickApp: App {
    @State private var model = AppModel()
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("accentBlue") private var accentRaw = AccentBlue.ultramarin.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .nbAccentFromStorage()
                .preferredColorScheme(colorScheme)
                .onChange(of: accentRaw, initial: true) { _, raw in model.mirrorAccent(raw) }
        }
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

/// Switches between onboarding and the main tabs, and handles widget deep links.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: Tab = .overview
    @State private var showSpeedTest = false

    enum Tab: Hashable { case overview, devices, diagnosis, settings }

    var body: some View {
        Group {
            if model.mode == .onboarding {
                OnboardingView()
            } else {
                tabs
            }
        }
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .onOpenURL { url in
            guard url.scheme == "netzblick" else { return }
            switch url.host {
            case "speedtest": tab = .overview; showSpeedTest = true
            case "diagnosis": tab = .diagnosis
            default: tab = .overview
            }
        }
        .sheet(isPresented: $showSpeedTest) {
            SpeedTestView()
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            NavigationStack { OverviewView(onStartSpeedTest: { showSpeedTest = true }) }
                .tabItem { Label("Übersicht", systemImage: "house") }
                .tag(Tab.overview)
            NavigationStack { DevicesView() }
                .tabItem { Label("Geräte", systemImage: "rectangle.on.rectangle") }
                .tag(Tab.devices)
            NavigationStack { DiagnosisView(onStartSpeedTest: { showSpeedTest = true }) }
                .tabItem { Label("Diagnose", systemImage: "waveform.path.ecg") }
                .tag(Tab.diagnosis)
            NavigationStack {
                SettingsView(
                    boxName: model.boxName,
                    onDisconnect: { model.disconnect() },
                    onDeleteAll: { model.deleteAll() }
                )
            }
            .tabItem { Label("Einstellungen", systemImage: "gearshape") }
            .tag(Tab.settings)
        }
    }
}
