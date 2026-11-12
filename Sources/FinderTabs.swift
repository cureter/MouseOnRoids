// Mittelklick auf einen Ordner im Finder öffnet ihn in einem neuen Tab.
//
// Finder hat dafür keine Schnittstelle – aber ⌘-Doppelklick auf einen Ordner öffnet ihn
// in einem neuen Tab (bei der Standard-Einstellung "Ordner in Tabs statt in neuen
// Fenstern öffnen"). Genau diesen Klick erzeugen wir.

import Cocoa

enum FinderTabs {
    private static let finderID = "com.apple.finder"

    /// Prüft, ob unter dem Mauszeiger ein Ordner im Finder liegt, und öffnet ihn ggf. als Tab.
    /// Liefert true, wenn der Mittelklick damit erledigt ist.
    static func openFolderTab(at point: CGPoint, marker: Int64) -> Bool {
        guard let folder = folder(at: point) else { return false }
        Log.write("Finder: Ordner als Tab öffnen – \(folder.lastPathComponent)")
        commandDoubleClick(at: point, marker: marker)
        return true
    }

    // MARK: Ordner unter dem Mauszeiger finden

    static func folder(at point: CGPoint) -> URL? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == finderID else { return nil }

        var names: [String] = []
        var roles: [String] = []
        let containerRoles: Set<String> = ["AXList", "AXOutline", "AXTable", "AXBrowser", "AXScrollArea",
                                           "AXSplitGroup", "AXWindow"]

        for _ in 0..<8 {
            let role = string(element, kAXRoleAttribute) ?? "?"
            roles.append(role)

            // 1. Direkte Adresse des Objekts (Finder liefert sie für viele Einträge)
            if let url = url(element, kAXURLAttribute), isFolder(url) { return url }
            if containerRoles.contains(role) { break }

            // 2. Namen sammeln, um sie später mit dem Fensterordner zu kombinieren
            names += candidateNames(element)
            for child in children(element).prefix(6) { names += candidateNames(child) }

            guard let parent = parent(element) else { break }
            element = parent
        }

        // Ordner des Fensters (AXDocument) + Name des Eintrags; ohne Fenster: Schreibtisch-Symbole
        let baseDir: URL? = if let window = window(of: element) {
            url(window, kAXDocumentAttribute)
        } else {
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        }
        if let baseDir {
            for name in names where !name.isEmpty && !name.contains("/") {
                let candidate = baseDir.appendingPathComponent(name)
                if isFolder(candidate) { return candidate }
            }
        }
        Log.write("Finder: kein Ordner erkannt (Rollen: \(roles.joined(separator: " › ")), Namen: \(names.prefix(4)))")
        return nil
    }

    /// Echter Ordner – Programme und andere Pakete zählen nicht.
    private static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    // MARK: ⌘-Doppelklick erzeugen

    private static func commandDoubleClick(at point: CGPoint, marker: Int64) {
        for clickState in [1, 2] as [Int64] {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                guard let ev = CGEvent(mouseEventSource: nil, mouseType: type,
                                       mouseCursorPosition: point, mouseButton: .left) else { continue }
                ev.flags = .maskCommand
                ev.setIntegerValueField(.mouseEventClickState, value: clickState)
                ev.setIntegerValueField(.eventSourceUserData, value: marker)
                ev.post(tap: .cgSessionEventTap)
            }
        }
    }

    // MARK: Bedienungshilfen-Helfer

    private static func attribute(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
    }

    private static func string(_ e: AXUIElement, _ name: String) -> String? {
        attribute(e, name) as? String
    }

    private static func url(_ e: AXUIElement, _ name: String) -> URL? {
        guard let value = attribute(e, name) else { return nil }
        if CFGetTypeID(value) == CFURLGetTypeID() { return (value as! URL) }
        if let s = value as? String {
            return s.hasPrefix("file://") ? URL(string: s) : (s.hasPrefix("/") ? URL(fileURLWithPath: s) : nil)
        }
        return nil
    }

    private static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func parent(_ e: AXUIElement) -> AXUIElement? { element(attribute(e, kAXParentAttribute)) }

    private static func window(of e: AXUIElement) -> AXUIElement? {
        if string(e, kAXRoleAttribute) == "AXWindow" { return e }
        return element(attribute(e, kAXWindowAttribute))
    }

    private static func children(_ e: AXUIElement) -> [AXUIElement] {
        (attribute(e, kAXChildrenAttribute) as? [AnyObject] ?? []).compactMap { element($0) }
    }

    private static func candidateNames(_ e: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXFilenameAttribute]
            .compactMap { string(e, $0) }
    }
}
