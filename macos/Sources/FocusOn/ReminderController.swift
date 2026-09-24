import AppKit

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ReminderController {
    private(set) var panels: [PetPanel] = []
    private var animation: Timer?
    private var generation = 0
    private var shownAt = 0.0
    private var isShowing = false
    private var screenObserver: NSObjectProtocol?
    private var motionObserver: NSObjectProtocol?
    var isAnimating: Bool { animation?.isValid == true }
    var theme: PetTheme = .light {
        didSet {
            for panel in panels { (panel.contentView as? PetCompanionView)?.theme = theme }
        }
    }

    init() {
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isShowing else { return }
            self.hide(immediate: true); self.show()
        }
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.updateMotion() }
    }

    deinit {
        animation?.invalidate()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
        panels.forEach { $0.orderOut(nil) }
    }
    func show() {
        guard !isShowing else { return }
        hide(immediate: true)
        generation += 1; isShowing = true; shownAt = ProcessInfo.processInfo.systemUptime
        // Keep the companion visible on external displays without moving or activating any app.
        panels = NSScreen.screens.map { screen in
            let area = screen.frame
            let size = PetCompanionView.canvasSize
            let frame = NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                               width: size.width, height: size.height)
            let panel = PetPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            let pet = PetCompanionView(frame: NSRect(origin: .zero, size: frame.size))
            pet.theme = theme
            pet.reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            panel.contentView = pet
            panel.alphaValue = 0; panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25
                panel.animator().alphaValue = 1
            }
            return panel
        }
        updateMotion()
    }

    private func updateMotion() {
        animation?.invalidate(); animation = nil
        guard isShowing else { return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for panel in panels {
            if let pet = panel.contentView as? PetCompanionView {
                pet.reducedMotion = reduced
                pet.time = ProcessInfo.processInfo.systemUptime - shownAt
                pet.needsDisplay = true
            }
        }
        guard !reduced else { return }
        animation = Timer(timeInterval: 1.0 / 24, repeats: true) { [weak self] _ in
            guard let self else { return }
            for panel in self.panels {
                if let pet = panel.contentView as? PetCompanionView {
                    pet.time = ProcessInfo.processInfo.systemUptime - self.shownAt
                    pet.needsDisplay = true
                }
            }
        }
        animation?.tolerance = 0.008
        RunLoop.main.add(animation!, forMode: .common)
    }
    func hide(immediate: Bool = false) {
        guard isShowing || immediate else { return }
        isShowing = false; generation += 1
        let token = generation
        animation?.invalidate(); animation = nil
        guard !panels.isEmpty else { return }
        if immediate {
            panels.forEach { $0.orderOut(nil) }; panels.removeAll(); return
        }
        let fading = panels
        for panel in fading { (panel.contentView as? PetCompanionView)?.returning = true; panel.contentView?.needsDisplay = true }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25
            fading.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            fading.forEach { $0.orderOut(nil) }
            if self?.generation == token { self?.panels.removeAll() }
        })
    }
    var visible: Bool { isShowing }
}
