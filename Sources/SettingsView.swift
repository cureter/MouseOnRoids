import SwiftUI
import ServiceManagement

/// Laufzeit-Zustand, den das Fenster anzeigt (Berechtigung, Engine aktiv?).
final class AppState: ObservableObject {
    @Published var trusted = false
    @Published var running = false
}

struct SettingsView: View {
    @ObservedObject var state: AppState

    @AppStorage(Key.enabled) private var enabled = true
    @AppStorage(Key.step) private var step = 60.0
    @AppStorage(Key.smoothness) private var smoothness = 0.12
    @AppStorage(Key.acceleration) private var acceleration = 0.5
    @AppStorage(Key.reverseVertical) private var reverseVertical = false
    @AppStorage(Key.reverseHorizontal) private var reverseHorizontal = false
    @AppStorage(Key.shiftHorizontal) private var shiftHorizontal = true
    @AppStorage(Key.showMenuIcon) private var showMenuIcon = true
    @AppStorage(Key.autoscroll) private var autoscroll = true
    @AppStorage(Key.autoscrollSpeed) private var autoscrollSpeed = 1.0
    @AppStorage(Key.autoscrollKeepLinks) private var autoscrollKeepLinks = true
    @AppStorage(Key.finderMiddleTab) private var finderMiddleTab = true
    @State private var excluded: [String] = Settings.excludedApps
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                statusRow
                Toggle("Sanftes Scrollen aktiviert", isOn: $enabled)
            }

            Section {
                Picker("Voreinstellung", selection: presetBinding) {
                    ForEach(Preset.allCases) { Text($0.title).tag(Optional($0)) }
                    if presetBinding.wrappedValue == nil { Text("Eigene").tag(Preset?.none) }
                }
                .pickerStyle(.segmented)

                sliderRow("Scroll-Distanz pro Raste", value: $step, range: 10...200,
                          text: "\(Int(step)) px",
                          hint: "Kleiner = weniger Strecke pro Klick am Mausrad.")
                sliderRow("Weichheit", value: $smoothness, range: 0.02...0.35,
                          text: "\(Int(smoothness * 1000)) ms",
                          hint: "Wie lange das Scrollen nach jeder Raste ausrollt.")
                sliderRow("Beschleunigung", value: $acceleration, range: 0...1,
                          text: acceleration < 0.01 ? "aus" : "\(Int(acceleration * 100)) %",
                          hint: "Schnelles Drehen scrollt weiter. „aus“ = jede Raste gleich weit.")
            } header: { Text("Scrollverhalten") }

            Section {
                Toggle("Vertikal umkehren", isOn: $reverseVertical)
                Toggle("Horizontal umkehren", isOn: $reverseHorizontal)
                Toggle("Shift + Mausrad scrollt waagerecht", isOn: $shiftHorizontal)
            } header: { Text("Richtung (nur Maus, Trackpad bleibt unverändert)") }

            Section {
                Toggle("Autoscroll mit der mittleren Maustaste", isOn: $autoscroll)
                if autoscroll {
                    sliderRow("Autoscroll-Tempo", value: $autoscrollSpeed, range: 0.3...3,
                              text: "\(Int(autoscrollSpeed * 100)) %",
                              hint: "Je weiter du die Maus vom Startpunkt wegbewegst, desto schneller scrollt es.")
                    Toggle("Mittelklick auf Links und Tabs normal lassen", isOn: $autoscrollKeepLinks)
                }
                Toggle("Finder: Mittelklick auf Ordner öffnet ihn als Tab", isOn: $finderMiddleTab)
            } header: {
                Text("Mittlere Maustaste (wie unter Windows)")
            } footer: {
                Text("Kurz klicken: scrollt in Richtung der Maus, bis du erneut klickst. Gedrückt halten: scrollt, bis du loslässt. Auf Links öffnet der Mittelklick weiterhin einen neuen Tab, auf Tabs schließt er sie.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if excluded.isEmpty {
                    Text("Keine – MouseOnRoids wirkt in allen Apps.")
                        .foregroundStyle(.secondary)
                }
                ForEach(excluded, id: \.self) { id in
                    HStack {
                        appLabel(id)
                        Spacer()
                        Button(role: .destructive) { remove(id) } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                    }
                }
                Menu("App hinzufügen…") {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                            if let id = app.bundleIdentifier { add(id) }
                        }
                    }
                }
                .fixedSize()
            } header: {
                Text("Ausnahmen")
            } footer: {
                Text("In diesen Apps scrollt die Maus wie ohne MouseOnRoids – z. B. für Spiele oder Programme mit eigenem Scrollen.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(1...80, id: \.self) { i in
                            Text("Zeile \(i) – hier kannst du das Scrollen mit deiner Maus ausprobieren")
                                .foregroundStyle(i % 10 == 0 ? .primary : .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .frame(height: 160)
            } header: { Text("Testbereich") }

            Section {
                Toggle("Bei Anmeldung starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin($0) }
                Toggle("Symbol in der Menüleiste anzeigen", isOn: $showMenuIcon)
                if !showMenuIcon {
                    Text("Ohne Symbol öffnest du dieses Fenster, indem du MouseOnRoids im Programme-Ordner erneut startest.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Standardwerte wiederherstellen") { Defaults.reset() }
                    Spacer()
                    Button("MouseOnRoids beenden") { NSApp.terminate(nil) }
                }
            } header: { Text("Allgemein") }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .frame(minHeight: 500)
    }

    // MARK: Bausteine

    @ViewBuilder private var statusRow: some View {
        if state.running {
            Label("Läuft – Mausrad wird geglättet", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Bedienungshilfen-Zugriff fehlt", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Solange der Zugriff fehlt, scrollt die Maus ganz normal wie ohne MouseOnRoids. Erlaube MouseOnRoids unter Datenschutz & Sicherheit → Bedienungshilfen.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Systemeinstellungen öffnen") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           text: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(text).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func appLabel(_ id: String) -> some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        let name = url.map { FileManager.default.displayName(atPath: $0.path) } ?? id
        return HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().frame(width: 18, height: 18)
            }
            Text(name.replacingOccurrences(of: ".app", with: ""))
        }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                      && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                      && !excluded.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func add(_ id: String) {
        excluded.append(id)
        UserDefaults.standard.set(excluded, forKey: Key.excludedApps)
    }

    private func remove(_ id: String) {
        excluded.removeAll { $0 == id }
        UserDefaults.standard.set(excluded, forKey: Key.excludedApps)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            let alert = NSAlert()
            alert.messageText = "Autostart konnte nicht geändert werden"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    // MARK: Voreinstellungen

    enum Preset: String, CaseIterable, Identifiable {
        case precise, balanced, fast
        var id: String { rawValue }
        var title: String {
            switch self {
            case .precise: "Präzise"
            case .balanced: "Ausgewogen"
            case .fast: "Schnell"
            }
        }
        var values: (step: Double, smoothness: Double, acceleration: Double) {
            switch self {
            case .precise: (35, 0.08, 0)
            case .balanced: (60, 0.12, 0.5)
            case .fast: (110, 0.16, 0.8)
            }
        }
    }

    private var presetBinding: Binding<Preset?> {
        Binding(
            get: {
                Preset.allCases.first {
                    abs($0.values.step - step) < 0.5 && abs($0.values.smoothness - smoothness) < 0.001
                        && abs($0.values.acceleration - acceleration) < 0.001
                }
            },
            set: { preset in
                guard let v = preset?.values else { return }
                step = v.step; smoothness = v.smoothness; acceleration = v.acceleration
            }
        )
    }
}
