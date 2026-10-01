import AppKit

enum PetTheme: String {
    case light, dark

    var bodyColor: NSColor {
        switch self {
        case .light: return NSColor(srgbRed: 0.286, green: 0.416, blue: 0.365, alpha: 1)
        case .dark: return NSColor(srgbRed: 214.0 / 255, green: 233.0 / 255, blue: 47.0 / 255, alpha: 1)
        }
    }

    var eyeColor: NSColor {
        switch self {
        case .light: return NSColor(srgbRed: 0.98, green: 0.975, blue: 0.96, alpha: 1)
        case .dark: return NSColor(srgbRed: 27.0 / 255, green: 26.0 / 255, blue: 25.0 / 255, alpha: 1)
        }
    }
}

/// A quiet 12-second loop: pause between glances, with short, smooth blinks.
struct PetPose {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var openness: CGFloat = 1

    static func at(_ time: Double, reducedMotion: Bool, returning: Bool = false) -> PetPose {
        guard !reducedMotion else { return PetPose() }
        guard !returning else { return PetPose(openness: 0.14) }
        let phase = max(0, time).truncatingRemainder(dividingBy: 12)
        let stops: [(Double, CGFloat, CGFloat)] = [
            (0, 0, 0), (1.3, 0, 0), (1.7, -13, 0), (2.7, -13, 0),
            (3.2, 13, 0), (4.2, 13, 0), (4.6, 0, 0), (5.6, 0, 0),
            (6.0, 0, 10), (7.0, 0, 10), (7.5, 0, -10), (8.5, 0, -10),
            (8.9, 0, 0), (12, 0, 0)
        ]
        var pose = PetPose()
        for (start, end) in zip(stops, stops.dropFirst()) where phase >= start.0 && phase < end.0 {
            let t = CGFloat((phase - start.0) / (end.0 - start.0))
            let eased = t * t * (3 - 2 * t)
            pose.x = start.1 + (end.1 - start.1) * eased
            pose.y = start.2 + (end.2 - start.2) * eased
            break
        }
        for blinkStart in [0.7, 4.9, 9.7] {
            let t = (phase - blinkStart) / 0.28
            if t >= 0 && t <= 1 {
                pose.openness = 1 - 0.86 * CGFloat(pow(sin(t * .pi), 2))
            }
        }
        return pose
    }
}

class PetCompanionView: NSView {
    static let canvasSize = NSSize(width: 720, height: 500)
    var time: Double = 0
    var theme: PetTheme = .light { didSet { needsDisplay = true } }
    var returning = false
    var reducedMotion = false
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let pose = PetPose.at(time, reducedMotion: reducedMotion, returning: returning)
        let canvas = NSRect(x: 0, y: 0, width: 192, height: 180)
        let scale = min(bounds.width / canvas.width, bounds.height / canvas.height)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: bounds.midX - canvas.midX * scale, yBy: bounds.midY - canvas.midY * scale)
        transform.scale(by: scale)
        transform.concat()
        // Match the reference silhouette: no mouth, limbs, surrounding card or text.
        let body = NSRect(x: canvas.midX - 71, y: canvas.midY - 64, width: 142, height: 128)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.set()
        theme.bodyColor.setFill()
        NSBezierPath(roundedRect: body, xRadius: 53, yRadius: 53).fill()
        NSGraphicsContext.restoreGraphicsState()

        theme.eyeColor.setFill()
        for offset: CGFloat in [-15, 15] {
            let height = 37 * pose.openness
            let width = 15 + 8 * (1 - pose.openness)
            let eye = NSRect(x: canvas.midX + offset + pose.x - width / 2,
                             y: canvas.midY + pose.y - height / 2, width: width, height: height)
            NSBezierPath(roundedRect: eye, xRadius: min(width, height) / 2,
                         yRadius: min(width, height) / 2).fill()
        }
    }
}
