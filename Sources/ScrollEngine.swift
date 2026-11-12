// Prinzip: Ein CGEventTap fängt die Scroll-Ereignisse des Mausrads ab (nur
// "diskrete" Rad-Ereignisse – Trackpad / Magic Mouse bleiben unberührt).
// Statt der von macOS beschleunigten Zeilen-Sprünge wird pro Rad-Raste eine
// feste, einstellbare Pixel-Strecke weich animiert gescrollt.

import Cocoa

/// Markierung für selbst erzeugte Ereignisse, damit der Tap sie nicht erneut abfängt.
let kSyntheticMarker: Int64 = 0x5343_524C // "SCRL"

final class ScrollEngine {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var timer: Timer?
    private var lastFrame: CFTimeInterval = 0

    // Noch zu scrollende Strecke (Pixel) und Nachkommareste
    private var remainingY = 0.0, remainingX = 0.0
    private var carryY = 0.0, carryX = 0.0

    // Für die Beschleunigung: Zeitpunkt der letzten Raste je Achse
    private var lastTickY: CFTimeInterval = 0, lastTickX: CFTimeInterval = 0

    let autoScroller = AutoScroller()

    var isRunning: Bool { tap != nil }

    init() {
        autoScroller.post = { [weak self] dy, dx in self?.post(dy: dy, dx: dx) }
    }

    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.scrollWheel, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                    .otherMouseDown, .otherMouseUp, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let engine = Unmanaged<ScrollEngine>.fromOpaque(refcon!).takeUnretainedValue()
                return engine.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else { return false }

        tap = port
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    /// Tap komplett entfernen – danach erreichen alle Rad-Ereignisse wieder ungefiltert die Apps.
    func stop() {
        guard let port = tap else { return }
        autoScroller.stop()
        CGEvent.tapEnable(tap: port, enable: false)
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        CFMachPortInvalidate(port)
        tap = nil
        runLoopSource = nil
        timer?.invalidate()
        timer = nil
        remainingY = 0; remainingX = 0; carryY = 0; carryX = 0
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS deaktiviert Taps, die zu langsam sind – sofort wieder einschalten.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // Eigene Ereignisse durchlassen
        if event.getIntegerValueField(.eventSourceUserData) == kSyntheticMarker {
            return Unmanaged.passUnretained(event)
        }
        // Mausklicks gehen an den Autoscroll (mittlere Taste). Laufende Autoscrolls
        // müssen auch dann sauber beendet werden, wenn MouseOnRoids gerade aus ist.
        if type != .scrollWheel || autoScroller.active {
            let mayStart = Settings.enabled && !isFrontmostExcluded()
            if autoScroller.handle(type: type, event: event, mayStart: mayStart) { return nil }
            if type != .scrollWheel { return Unmanaged.passUnretained(event) }
        }
        guard Settings.enabled else {
            return Unmanaged.passUnretained(event)
        }
        // Trackpad / Magic Mouse (kontinuierlich) nicht anfassen
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
            return Unmanaged.passUnretained(event)
        }
        // Mit Cmd / Ctrl / Option (z. B. Zoomen) unverändert durchreichen
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            return Unmanaged.passUnretained(event)
        }
        // Ausgeschlossene Apps
        if isFrontmostExcluded() {
            return Unmanaged.passUnretained(event)
        }

        var dy = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        var dx = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        if dy == 0 && dx == 0 {
            // Manche Mäuse liefern nur Punkt-Deltas
            dy = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1).signum()
            dx = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2).signum()
            if dy == 0 && dx == 0 { return Unmanaged.passUnretained(event) }
        }
        // Shift + Rad = horizontal scrollen
        if flags.contains(.maskShift) && Settings.shiftHorizontal && dx == 0 {
            dx = dy; dy = 0
        }

        let now = CACurrentMediaTime()
        if dy != 0 {
            let sign: Double = Settings.reverseVertical ? -1 : 1
            addTick(&remainingY, direction: Double(dy.signum()) * sign, lastTick: &lastTickY, now: now)
        }
        if dx != 0 {
            let sign: Double = Settings.reverseHorizontal ? -1 : 1
            addTick(&remainingX, direction: Double(dx.signum()) * sign, lastTick: &lastTickX, now: now)
        }

        startAnimating()
        return nil // Original-Ereignis verwerfen
    }

    private func isFrontmostExcluded() -> Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return Settings.excludedApps.contains(id)
    }

    private func addTick(_ remaining: inout Double, direction: Double, lastTick: inout CFTimeInterval, now: CFTimeInterval) {
        // Beschleunigung: je schneller die Rasten aufeinander folgen, desto größer der Schritt
        let interval = now - lastTick
        lastTick = now
        let speed = max(0, min(1, (0.09 - interval) / 0.07))   // 0 bei ≥90 ms, 1 bei ≤20 ms
        let factor = 1 + Settings.acceleration * 2.5 * speed * speed
        let amount = Settings.step * factor * direction

        // Richtungswechsel: Rest verwerfen, damit es sofort reagiert
        if remaining != 0 && (remaining > 0) != (amount > 0) { remaining = 0 }
        remaining += amount
    }

    private func startAnimating() {
        guard timer == nil else { return }
        lastFrame = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.frame() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func frame() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastFrame, 0.05)
        lastFrame = now

        let tau = max(0.01, Settings.smoothness)
        let k = 1 - exp(-dt / tau)

        let py = step(&remainingY, carry: &carryY, k: k)
        let px = step(&remainingX, carry: &carryX, k: k)

        if py != 0 || px != 0 { post(dy: py, dx: px) }

        if remainingY == 0 && remainingX == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Liefert die ganzzahligen Pixel für diesen Frame.
    private func step(_ remaining: inout Double, carry: inout Double, k: Double) -> Int32 {
        guard remaining != 0 else { return 0 }
        var move = remaining * k
        // Am Ende nicht ewig "ausschleichen"
        if abs(remaining) < 1 { move = remaining }
        else if abs(move) < 1 { move = remaining > 0 ? 1 : -1 }
        remaining -= move
        if abs(remaining) < 0.01 { remaining = 0 }

        carry += move
        let whole = carry.rounded(.towardZero)
        carry -= whole
        return Int32(whole)
    }

    private func post(dy: Int32, dx: Int32) {
        guard let ev = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                               wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        ev.setIntegerValueField(.eventSourceUserData, value: kSyntheticMarker)
        ev.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        ev.flags = []
        ev.post(tap: .cgSessionEventTap)
    }
}
