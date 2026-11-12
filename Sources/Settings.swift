import Foundation

/// Gemeinsame Schlüssel für UserDefaults – die Oberfläche nutzt sie per @AppStorage,
/// die Scroll-Engine liest sie direkt.
enum Key {
    static let enabled = "enabled"
    static let step = "step"                     // Pixel pro Rad-Raste
    static let smoothness = "smoothness"         // Zeitkonstante der Animation (Sekunden)
    static let acceleration = "acceleration"     // 0 = linear … 1 = stark
    static let reverseVertical = "reverseVertical"
    static let reverseHorizontal = "reverseHorizontal"
    static let shiftHorizontal = "shiftHorizontal"
    static let excludedApps = "excludedApps"     // Bundle-IDs, in denen nichts verändert wird
    static let showMenuIcon = "showMenuIcon"
    static let autoscroll = "autoscroll"                   // Mittlere Taste = Autoscroll wie unter Windows
    static let autoscrollSpeed = "autoscrollSpeed"         // Faktor 0.3 … 3
    static let autoscrollKeepLinks = "autoscrollKeepLinks" // Mittelklick auf Links/Tabs normal lassen
    static let finderMiddleTab = "finderMiddleTab"         // Mittelklick auf Ordner im Finder → neuer Tab
}

enum Defaults {
    static let values: [String: Any] = [
        Key.enabled: true,
        Key.step: 60.0,
        Key.smoothness: 0.12,
        Key.acceleration: 0.5,
        Key.reverseVertical: false,
        Key.reverseHorizontal: false,
        Key.shiftHorizontal: true,
        Key.excludedApps: [String](),
        Key.showMenuIcon: true,
        Key.autoscroll: true,
        Key.autoscrollSpeed: 1.0,
        Key.autoscrollKeepLinks: true,
        Key.finderMiddleTab: true,
    ]

    static func register() { UserDefaults.standard.register(defaults: values) }

    static func reset() {
        for key in values.keys where key != Key.excludedApps && key != Key.showMenuIcon {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

struct Settings {
    private static var d: UserDefaults { .standard }
    static var enabled: Bool { d.bool(forKey: Key.enabled) }
    static var step: Double { d.double(forKey: Key.step) }
    static var smoothness: Double { d.double(forKey: Key.smoothness) }
    static var acceleration: Double { d.double(forKey: Key.acceleration) }
    static var reverseVertical: Bool { d.bool(forKey: Key.reverseVertical) }
    static var reverseHorizontal: Bool { d.bool(forKey: Key.reverseHorizontal) }
    static var shiftHorizontal: Bool { d.bool(forKey: Key.shiftHorizontal) }
    static var excludedApps: [String] { d.stringArray(forKey: Key.excludedApps) ?? [] }
    static var autoscroll: Bool { d.bool(forKey: Key.autoscroll) }
    static var autoscrollSpeed: Double { d.double(forKey: Key.autoscrollSpeed) }
    static var autoscrollKeepLinks: Bool { d.bool(forKey: Key.autoscrollKeepLinks) }
    static var finderMiddleTab: Bool { d.bool(forKey: Key.finderMiddleTab) }
}
