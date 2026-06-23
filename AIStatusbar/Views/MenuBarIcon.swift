import AppKit
import SwiftUI

/// Renders the menu bar icon as a small cartoon blue bird (Vocabby-inspired).
/// Drawn programmatically with Core Graphics paths so it renders identically
/// on light and dark menu bars with no asset dependency.
enum MenuBarIconRenderer {
    /// Render a bird NSImage sized for a 22pt menu bar slot.
    static func image(size: NSSize = NSSize(width: 22, height: 18)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        // Geometry — bird centered in the 22x18 frame, facing right
        let frame = NSRect(origin: .zero, size: size)
        let cx = frame.midX
        let cy = frame.midY

        // Colors
        let bodyBlue = NSColor(calibratedRed: 0.231, green: 0.510, blue: 0.965, alpha: 1.0)  // #3B82F6
        let cream    = NSColor(calibratedRed: 0.984, green: 0.965, blue: 0.918, alpha: 1.0)  // #FBF6E6
        let beakOrange = NSColor(calibratedRed: 0.976, green: 0.620, blue: 0.094, alpha: 1.0)  // #F89E18
        let eyeBlack = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.15, alpha: 1.0)

        // Body (oval, slightly bigger than head)
        let bodyRect = NSRect(x: cx - 7, y: cy - 5, width: 13, height: 10)
        bodyBlue.setFill()
        NSBezierPath(ovalIn: bodyRect).fill()

        // Belly (cream highlight on lower body)
        let bellyRect = NSRect(x: cx - 4, y: cy - 4, width: 8, height: 5)
        cream.setFill()
        NSBezierPath(ovalIn: bellyRect).fill()

        // Head (smaller circle, top-right of body)
        let headRect = NSRect(x: cx + 2, y: cy - 2, width: 8, height: 8)
        bodyBlue.setFill()
        NSBezierPath(ovalIn: headRect).fill()

        // Eye
        let eyeRect = NSRect(x: cx + 6, y: cy + 2, width: 1.5, height: 1.5)
        eyeBlack.setFill()
        NSBezierPath(ovalIn: eyeRect).fill()

        // Beak (triangle, pointing right)
        let beakPath = NSBezierPath()
        beakPath.move(to: NSPoint(x: cx + 10, y: cy + 1.5))
        beakPath.line(to: NSPoint(x: cx + 13, y: cy + 0.5))
        beakPath.line(to: NSPoint(x: cx + 10, y: cy - 0.5))
        beakPath.close()
        beakOrange.setFill()
        beakPath.fill()

        // Wing (small oval on body, slightly darker for depth)
        let wingPath = NSBezierPath(ovalIn: NSRect(x: cx - 3, y: cy - 1, width: 6, height: 4))
        NSColor(calibratedRed: 0.180, green: 0.420, blue: 0.870, alpha: 1.0).setFill()
        wingPath.fill()

        // Feet (two small orange ovals at bottom)
        beakOrange.setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - 3, y: cy - 6, width: 2, height: 1.5)).fill()
        NSBezierPath(ovalIn: NSRect(x: cx + 1, y: cy - 6, width: 2, height: 1.5)).fill()

        return image
    }
}

