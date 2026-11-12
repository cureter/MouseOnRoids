// Autoscroll wie unter Windows: Mittlere Maustaste drücken, Maus vom Startpunkt
// wegbewegen – es scrollt in diese Richtung, umso schneller, je weiter weg.
//
// - Kurz klicken: Autoscroll bleibt an, bis zum nächsten Mausklick.
// - Gedrückt halten und ziehen: Autoscroll endet beim Loslassen.
// - Auf Links und Tabs bleibt der normale Mittelklick erhalten (neuer Tab / Tab schließen).

import Cocoa

final class AutoScroller {
    /// Sendet ein Pixel-Scroll-Ereignis (wird von der ScrollEngine bereitgestellt).
    var post: (_ dy: Int32, _ dx: Int32) -> Void = { _, _ in }

    private(set) var active = false
    private var anchor = CGPoint.zero
    private var downTime: CFTimeInterval = 0
    private var timer: Timer?
    private var lastFrame: CFTimeInterval = 0
    private var carryX = 0.0, carryY = 0.0
    /// Tasten, deren nächstes "Loslassen" wir schlucken müssen, weil wir das Drücken geschluckt haben.
    private var swallowUp = Set<Int64>()
    private let indicator = AutoScrollIndicator()
    private var axEnabledPids = Set<pid_t>()

    private let middleButton: Int64 = 2
    private let deadZone = 12.0

    init() {
        // Chrome & Electron-Apps bauen ihren Bedienungshilfen-Baum (nötig für die Link-Erkennung)
        // erst auf, wenn man darum bittet – das passiert beim Aktivieren der App.
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.enableAccessibilityTree(pid: app.processIdentifier)
        }
    }

    /// Liefert true, wenn das Ereignis verschluckt werden soll.
    /// `mayStart`: ob an dieser Stelle ein neuer Autoscroll beginnen darf (MouseOnRoids aktiv, App nicht ausgenommen).
    func handle(type: CGEventType, event: CGEvent, mayStart: Bool) -> Bool {
        let button = event.getIntegerValueField(.mouseEventButtonNumber)

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if active {
                // Jeder Klick beendet den Autoscroll (wie unter Windows) und wird verschluckt.
                stop()
                swallowUp.insert(button)
                return true
            }
            guard type == .otherMouseDown, button == middleButton, mayStart else { return false }
            // Finder: Mittelklick auf einen Ordner öffnet ihn als Tab
            if Settings.finderMiddleTab && FinderTabs.openFolderTab(at: event.location, marker: kSyntheticMarker) {
                swallowUp.insert(button)
                return true
            }
            guard Settings.autoscroll else { return false }
            if Settings.autoscrollKeepLinks && middleClickBelongsToApp(at: event.location) { return false }
            start(at: event.location)
            return true

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            if swallowUp.remove(button) != nil { return true }
            if active && type == .otherMouseUp && button == middleButton {
                // Gedrückt gehalten oder gezogen → Halten-Modus endet jetzt.
                // Kurzer Klick ohne Bewegung → bleibt an bis zum nächsten Klick.
                let moved = distance(currentLocation(), anchor)
                if CACurrentMediaTime() - downTime > 0.35 || moved > deadZone { stop() }
                return true
            }
            return false

        case .otherMouseDragged:
            return active

        case .scrollWheel:
            if active { stop() }
            return false

        default:
            return false
        }
    }

    // MARK: Ablauf

    private func start(at point: CGPoint) {
        active = true
        anchor = point
        downTime = CACurrentMediaTime()
        carryX = 0; carryY = 0
        indicator.show(at: point)
        Log.write("Autoscroll gestartet")

        lastFrame = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.frame() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        guard active else { return }
        active = false
        timer?.invalidate()
        timer = nil
        indicator.hide()
    }

    private func frame() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastFrame, 0.05)
        lastFrame = now

        let p = currentLocation()
        let vy = velocity(p.y - anchor.y)
        let vx = velocity(p.x - anchor.x)
        indicator.update(dx: p.x - anchor.x, dy: p.y - anchor.y, deadZone: deadZone)

        // Maus unterhalb des Startpunkts → weiter nach unten scrollen (negatives Rad-Delta).
        carryY += -vy * dt
        carryX += -vx * dt
        let wy = carryY.rounded(.towardZero), wx = carryX.rounded(.towardZero)
        carryY -= wy; carryX -= wx
        if wy != 0 || wx != 0 { post(Int32(wy), Int32(wx)) }
    }

    /// Geschwindigkeit in Pixel/Sekunde abhängig vom Abstand zum Startpunkt.
    private func velocity(_ offset: Double) -> Double {
        let e = abs(offset) - deadZone
        guard e > 0 else { return 0 }
        let v = (8 * e + 0.04 * e * e) * Settings.autoscrollSpeed
        return offset < 0 ? -v : v
    }

    private func currentLocation() -> CGPoint { CGEvent(source: nil)?.location ?? anchor }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }

    // MARK: Link- / Tab-Erkennung über die Bedienungshilfen

    /// true = Mittelklick unverändert an die App weitergeben (Link, Tab, Knopf, Symbolleiste).
    private func middleClickBelongsToApp(at point: CGPoint) -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return false }

        var pid: pid_t = 0
        if AXUIElementGetPid(element, &pid) == .success { enableAccessibilityTree(pid: pid) }

        let passRoles: Set<String> = ["AXLink", "AXTab", "AXTabGroup", "AXRadioButton", "AXButton",
                                      "AXPopUpButton", "AXMenuButton", "AXToolbar", "AXMenuBar", "AXMenuItem"]
        let scrollRoles: Set<String> = ["AXWebArea", "AXScrollArea", "AXWindow"]

        for _ in 0..<15 {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            if let role = role as? String {
                if passRoles.contains(role) { return true }
                if scrollRoles.contains(role) { return false }
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
            element = parent as! AXUIElement
        }
        return false
    }

    private func enableAccessibilityTree(pid: pid_t) {
        guard Settings.autoscroll, Settings.autoscrollKeepLinks, !axEnabledPids.contains(pid) else { return }
        axEnabledPids.insert(pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
}

// MARK: - Anzeige am Startpunkt

final class AutoScrollIndicator {
    private let size: CGFloat = 34
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.contentView = view
        return p
    }()
    private let view = IndicatorView()

    func show(at cgPoint: CGPoint) {
        // CG-Koordinaten (Ursprung oben links) → AppKit (Ursprung unten links des Hauptbildschirms)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let origin = NSPoint(x: cgPoint.x - size / 2, y: primaryHeight - cgPoint.y - size / 2)
        view.direction = .zero
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    func update(dx: Double, dy: Double, deadZone: Double) {
        let d = CGVector(dx: abs(dx) > deadZone ? (dx > 0 ? 1 : -1) : 0,
                         dy: abs(dy) > deadZone ? (dy > 0 ? 1 : -1) : 0)
        if d != view.direction { view.direction = d; view.needsDisplay = true }
    }

    func hide() { panel.orderOut(nil) }
}

private final class IndicatorView: NSView {
    /// Aktive Richtung (x: -1 links / 1 rechts, y: -1 oben / 1 unten in Bildschirm-Logik)
    var direction = CGVector.zero

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 2, dy: 2)
        let circle = NSBezierPath(ovalIn: r)
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        circle.fill()
        NSColor.secondaryLabelColor.setStroke()
        circle.lineWidth = 1.5
        circle.stroke()

        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)).fill()

        // Pfeile: oben, unten, links, rechts (AppKit: y nach oben)
        let arrows: [(CGVector, CGVector)] = [
            (CGVector(dx: 0, dy: 1), CGVector(dx: 0, dy: -1)),   // oben ↔ Bildschirm-Richtung "hoch"
            (CGVector(dx: 0, dy: -1), CGVector(dx: 0, dy: 1)),   // unten
            (CGVector(dx: -1, dy: 0), CGVector(dx: -1, dy: 0)),  // links
            (CGVector(dx: 1, dy: 0), CGVector(dx: 1, dy: 0)),    // rechts
        ]
        for (dir, screenDir) in arrows {
            let isActive = (screenDir.dx != 0 && screenDir.dx == direction.dx)
                || (screenDir.dy != 0 && screenDir.dy == direction.dy)
            (isActive ? NSColor.controlAccentColor : NSColor.labelColor).setFill()
            triangle(center: c, dir: dir, distance: 10, size: 4.5).fill()
        }
    }

    private func triangle(center c: NSPoint, dir: CGVector, distance: CGFloat, size s: CGFloat) -> NSBezierPath {
        let tip = NSPoint(x: c.x + dir.dx * (distance + s), y: c.y + dir.dy * (distance + s))
        let base = NSPoint(x: c.x + dir.dx * distance, y: c.y + dir.dy * distance)
        let perp = CGVector(dx: -dir.dy, dy: dir.dx)
        let p = NSBezierPath()
        p.move(to: tip)
        p.line(to: NSPoint(x: base.x + perp.dx * s, y: base.y + perp.dy * s))
        p.line(to: NSPoint(x: base.x - perp.dx * s, y: base.y - perp.dy * s))
        p.close()
        return p
    }
}
