import AppKit

/// Smile for most of the three-second loop, with a brief, softly closed right eye.
struct PhasePetPose {
    let entrance: CGFloat
    let bob: CGFloat
    let wink: CGFloat

    static func at(_ time: Double, reducedMotion: Bool) -> Self {
        guard !reducedMotion else { return Self(entrance: 1, bob: 0, wink: 0) }
        let entry = min(1, max(0, time / 0.5))
        let phase = max(0, time - 0.5).truncatingRemainder(dividingBy: 3)
        let wink = phase >= 2 && phase <= 2.25 ? sin((phase - 2) / 0.25 * .pi) : 0
        return Self(entrance: CGFloat(1 - pow(1 - entry, 3)),
                    bob: CGFloat(sin(phase / 3 * 2 * .pi) * 2), wink: CGFloat(wink))
    }
}

/// A text-only, click-through reminder drawn at native size on the screen's edge.
final class PhaseReminderView: PetCompanionView {
    static let reminderSize = NSSize(width: 480, height: 268)
    let message: String
    // Original image-generation output, loaded once. No code-drawn pet fallback.
    static let sprite: NSImage = {
        guard let url = Bundle.module.url(forResource: "phase-peek", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("The generated phase pet is missing from the app bundle")
        }
        image.size = NSSize(width: 1254, height: 1254)
        return image
    }()
    // Alpha bounds measured in the unchanged atlas; normalize placement between frames.
    // Top row: light smile/wink; bottom row: dark smile/wink (image coordinates).
    static let spriteFrames = [NSRect(x: 189, y: 675, width: 322, height: 457),
                               NSRect(x: 750, y: 675, width: 329, height: 458),
                               NSRect(x: 189, y: 114, width: 322, height: 456),
                               NSRect(x: 750, y: 114, width: 329, height: 456)]

    static func petRect(in bounds: NSRect, pose: PhasePetPose) -> NSRect {
        // The generated art already includes the tilt. Keep its cut edge vertical
        // and just past the clipping boundary so it merges into the screen edge.
        NSRect(x: bounds.maxX - 160 + (1 - pose.entrance) * 180,
               y: bounds.midY - 110 + pose.bob + (1 - pose.entrance) * 10,
               width: 162, height: 220)
    }

    init(frame: NSRect, message: String) {
        self.message = message
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(message)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let palette = FocusPopoverPalette(dark: theme == .dark)
        let pose = PhasePetPose.at(time, reducedMotion: reducedMotion)
        let bubble = NSRect(x: 16, y: bounds.midY - 30, width: 288, height: 60)
        // The bubble stays still and appears only after the pet has settled.
        let opacity = reducedMotion ? 1 : min(1, max(0, (time - 0.4) / 0.2))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(opacity)
        let shape = NSBezierPath(roundedRect: bubble, xRadius: 30, yRadius: 30)
        palette.canvas.setFill(); shape.fill()
        palette.line.setStroke(); shape.lineWidth = 1; shape.stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: palette.text, .paragraphStyle: paragraph
        ]
        let text = NSAttributedString(string: message, attributes: attributes)
        let height = text.boundingRect(with: NSSize(width: 264, height: 60), options: .usesLineFragmentOrigin).height
        text.draw(with: NSRect(x: 28, y: bubble.midY - height / 2, width: 264, height: height), options: .usesLineFragmentOrigin)
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        NSGraphicsContext.current?.imageInterpolation = .high
        let source = Self.spriteFrames[(theme == .dark ? 2 : 0) + (pose.wink >= 0.5 ? 1 : 0)]
        Self.sprite.draw(in: Self.petRect(in: bounds, pose: pose),
                         from: source, operation: .sourceOver, fraction: 1)
    }
}
