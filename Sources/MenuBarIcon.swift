import AppKit

/// Symbole für die Menüleiste.
enum MenuBarIcon {
    /// Das Motiv des App-Icons ohne Hintergrund (Maus mit Blitz und Tempo-Streifen) als
    /// Vorlagenbild – macOS färbt es passend zur Menüleiste weiß oder schwarz.
    static let monochrome: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.set()

            // Tempo-Streifen
            for (y, x, w) in [(12.0, 1.5, 3.5), (9.0, 0.5, 4.5), (6.0, 2.0, 3.0)] as [(CGFloat, CGFloat, CGFloat)] {
                let line = NSBezierPath()
                line.move(to: NSPoint(x: x, y: y))
                line.line(to: NSPoint(x: x + w, y: y))
                line.lineWidth = 1.6
                line.lineCapStyle = .round
                line.stroke()
            }

            // Maus, leicht schräg wie im App-Icon
            let t = NSAffineTransform()
            t.translateX(by: 13, yBy: 9)
            t.rotate(byRadians: -0.26)
            t.concat()

            let body = NSBezierPath(roundedRect: NSRect(x: -4.6, y: -7.6, width: 9.2, height: 15.2),
                                    xRadius: 4.6, yRadius: 5)
            body.lineWidth = 1.5
            body.stroke()

            let wheel = NSBezierPath()
            wheel.move(to: NSPoint(x: 0, y: 2.4))
            wheel.line(to: NSPoint(x: 0, y: 5))
            wheel.lineWidth = 1.6
            wheel.lineCapStyle = .round
            wheel.stroke()

            let bolt = NSBezierPath()
            bolt.move(to: NSPoint(x: 0.9, y: 0.6))
            bolt.line(to: NSPoint(x: -2.0, y: -3.0))
            bolt.line(to: NSPoint(x: -0.2, y: -3.0))
            bolt.line(to: NSPoint(x: -1.1, y: -6.0))
            bolt.line(to: NSPoint(x: 2.2, y: -2.0))
            bolt.line(to: NSPoint(x: 0.4, y: -2.0))
            bolt.close()
            bolt.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MouseOnRoids"
        return image
    }()

    /// Das farbige App-Icon in Menüleisten-Größe.
    static let color: NSImage? = {
        let icon = NSApp.applicationIconImage.copy() as? NSImage
        icon?.size = NSSize(width: 20, height: 20)
        icon?.accessibilityDescription = "MouseOnRoids"
        return icon
    }()
}
