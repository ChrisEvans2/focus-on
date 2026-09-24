import AppKit

/// A transient, menu-anchored surface. It never becomes an application's key
/// or main window, including when its buttons are clicked from another app.
final class MenuBarHoverWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(content: NSView) {
        super.init(contentRect: content.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentView = content
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
    }

    static func frame(anchor: NSRect, size: NSSize, screen: NSRect) -> NSRect {
        let x = min(max(anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        let y = max(screen.minY + 8, min(anchor.minY - size.height - 6, screen.maxY - size.height - 6))
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    func show(anchor: NSRect, screen: NSScreen) {
        setFrame(Self.frame(anchor: anchor, size: frame.size, screen: screen.visibleFrame), display: false)
        // Ordering without activation keeps the foreground application's window
        // and keyboard focus unchanged. No parent/child window restoration occurs.
        orderFrontRegardless()
    }
}

final class HoverActionButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
}
