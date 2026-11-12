// MouseOnRoids – sanftes, kontrolliertes Scrollen für normale (Nicht-Apple-)Mäuse.

import Cocoa
import SwiftUI
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let engine = ScrollEngine()
    private let state = AppState()
    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!
    private var permissionItem: NSMenuItem!
    private var window: NSWindow?
    private var watchdog: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Defaults.register()
        lastEnabled = Settings.enabled
        Log.write("MouseOnRoids gestartet (Aktiviert: \(lastEnabled), \(Bundle.main.bundlePath))")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        buildMenu()

        // Erstmal nachfragen (zeigt den System-Dialog), danach regelmäßig prüfen.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        checkPermission()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)

        if !state.running { showSettings() }
    }

    // Erneutes Öffnen der App (z. B. aus dem Programme-Ordner) zeigt das Fenster.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    /// Ohne Bedienungshilfen-Zugriff darf der Tap nicht aktiv bleiben, sonst würde er
    /// die Rad-Ereignisse schlucken, ohne Ersatz senden zu dürfen – die Maus scrollt gar nicht mehr.
    private func checkPermission() {
        let ax = AXIsProcessTrusted()
        // Nur zur Info im Protokoll – dieser Wert wird von macOS erst nach einem Neustart aktualisiert.
        let canPost = CGPreflightPostEventAccess()
        let trusted = ax
        let wasRunning = engine.isRunning
        if trusted && !engine.isRunning { _ = engine.start() }
        if !trusted && engine.isRunning { engine.stop() }

        let snapshot = "AX=\(ax) Post=\(canPost) Tap=\(engine.isRunning)"
        if snapshot != lastPermissionSnapshot || wasRunning != engine.isRunning {
            lastPermissionSnapshot = snapshot
            Log.write("Berechtigung: \(snapshot)")
        }

        if state.trusted != trusted { state.trusted = trusted }
        if state.running != engine.isRunning {
            state.running = engine.isRunning
            refreshStatus()
        }
    }

    // MARK: Menüleiste

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        enabledItem = NSMenuItem(title: "Aktiviert", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)

        permissionItem = NSMenuItem(title: "⚠︎ Bedienungshilfen-Zugriff fehlt", action: #selector(showSettings), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Einstellungen…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "MouseOnRoids beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        refreshStatus()
    }

    func menuWillOpen(_ menu: NSMenu) { refreshStatus() }

    @objc private func defaultsChanged() {
        if Settings.enabled != lastEnabled {
            lastEnabled = Settings.enabled
            Log.write("Schalter „Aktiviert“: \(lastEnabled ? "an" : "aus")")
        }
        refreshStatus()
    }
    private var lastEnabled = true
    private var lastPermissionSnapshot = ""

    private func refreshStatus() {
        let enabled = Settings.enabled
        enabledItem.state = enabled ? .on : .off
        permissionItem.isHidden = engine.isRunning
        statusItem.isVisible = UserDefaults.standard.bool(forKey: Key.showMenuIcon)
        statusItem.button?.image = menuBarIcon
        // Ausgeschaltet oder ohne Berechtigung: Symbol abgeblendet
        statusItem.button?.alphaValue = enabled && engine.isRunning ? 1 : 0.4
    }

    /// Das App-Icon in Menüleisten-Größe
    private lazy var menuBarIcon: NSImage? = {
        let icon = NSApp.applicationIconImage.copy() as? NSImage
        icon?.size = NSSize(width: 20, height: 20)
        icon?.accessibilityDescription = "MouseOnRoids"
        return icon
    }()

    @objc private func toggleEnabled() {
        UserDefaults.standard.set(!Settings.enabled, forKey: Key.enabled)
    }

    // MARK: Einstellungsfenster

    @objc private func showSettings() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "MouseOnRoids"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(state: state))
            w.setContentSize(NSSize(width: 500, height: 720))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Einfaches Protokoll in ~/Library/Logs/MouseOnRoids.log zur Fehlersuche.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/MouseOnRoids.log")

    static func write(_ message: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard))  \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
