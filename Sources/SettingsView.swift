import SwiftUI
import ServiceManagement

/// Laufzeit-Zustand, den das Fenster anzeigt (Berechtigung, Engine aktiv?).
final class AppState: ObservableObject {
    @Published var trusted = false
    @Published var running = false
}

// Alle Texte sind englische Schlüssel; Übersetzungen liegen in Resources/<sprache>.lproj/Localizable.strings.
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
    @AppStorage(Key.monochromeMenuIcon) private var monochromeMenuIcon = true
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
                Toggle("Smooth scrolling enabled", isOn: $enabled)
            }

            Section {
                Picker("Preset", selection: presetBinding) {
                    ForEach(Preset.allCases) { Text($0.title).tag(Optional($0)) }
                    if presetBinding.wrappedValue == nil { Text("Custom").tag(Preset?.none) }
                }
                .pickerStyle(.segmented)

                sliderRow("Scroll distance per notch", value: $step, range: 10...200,
                          text: "\(Int(step)) px",
                          hint: "Smaller = less distance per click of the wheel.")
                sliderRow("Smoothness", value: $smoothness, range: 0.02...0.35,
                          text: "\(Int(smoothness * 1000)) ms",
                          hint: "How long scrolling glides after each notch.")
                sliderRow("Acceleration", value: $acceleration, range: 0...1,
                          text: acceleration < 0.01 ? String(localized: "off") : "\(Int(acceleration * 100)) %",
                          hint: "Spinning the wheel fast scrolls further. “off” = every notch scrolls the same.")
            } header: { Text("Scrolling") }

            Section {
                Toggle("Reverse vertical", isOn: $reverseVertical)
                Toggle("Reverse horizontal", isOn: $reverseHorizontal)
                Toggle("Shift + wheel scrolls horizontally", isOn: $shiftHorizontal)
            } header: { Text("Direction (mouse only, trackpad stays unchanged)") }

            Section {
                Toggle("Autoscroll with the middle mouse button", isOn: $autoscroll)
                if autoscroll {
                    sliderRow("Autoscroll speed", value: $autoscrollSpeed, range: 0.3...3,
                              text: "\(Int(autoscrollSpeed * 100)) %",
                              hint: "The further you move the mouse from the starting point, the faster it scrolls.")
                    Toggle("Keep normal middle-click on links and tabs", isOn: $autoscrollKeepLinks)
                }
                Toggle("Finder: middle-click a folder to open it in a new tab", isOn: $finderMiddleTab)
            } header: {
                Text("Middle mouse button (like on Windows)")
            } footer: {
                Text("Click once: scrolls toward the mouse until you click again. Hold: scrolls until you release. On links, middle-click still opens a new tab; on tabs, it closes them.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if excluded.isEmpty {
                    Text("None – MouseOnRoids works in all apps.")
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
                Menu("Add app…") {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                            if let id = app.bundleIdentifier { add(id) }
                        }
                    }
                }
                .fixedSize()
            } header: {
                Text("Exceptions")
            } footer: {
                Text("In these apps the mouse scrolls as if MouseOnRoids weren’t running – e.g. for games or apps with their own scrolling.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(1...80, id: \.self) { i in
                            Text("Line \(i) – try scrolling here with your mouse")
                                .foregroundStyle(i % 10 == 0 ? .primary : .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .frame(height: 160)
            } header: { Text("Test area") }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin($0) }
                Toggle("Show icon in the menu bar", isOn: $showMenuIcon)
                if showMenuIcon {
                    Picker("Menu bar icon", selection: $monochromeMenuIcon) {
                        Text("Monochrome").tag(true)
                        Text("Color").tag(false)
                    }
                    .pickerStyle(.segmented)
                } else {
                    Text("Without the icon, open this window by launching MouseOnRoids again from the Applications folder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Restore defaults") { Defaults.reset() }
                    Spacer()
                    Button("Quit MouseOnRoids") { NSApp.terminate(nil) }
                }
            } header: { Text("General") }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .frame(minHeight: 500)
    }

    // MARK: Bausteine

    @ViewBuilder private var statusRow: some View {
        if state.running {
            Label("Running – mouse wheel is being smoothed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Accessibility permission missing", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Until access is granted, the mouse scrolls normally, as without MouseOnRoids. Allow MouseOnRoids under Privacy & Security → Accessibility.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
    }

    private func sliderRow(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>,
                           text: String, hint: LocalizedStringKey) -> some View {
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
            alert.messageText = String(localized: "Could not change launch at login")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    // MARK: Voreinstellungen

    enum Preset: String, CaseIterable, Identifiable {
        case precise, balanced, fast
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .precise: "Precise"
            case .balanced: "Balanced"
            case .fast: "Fast"
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
