import AppKit
import FocusCore

/// The hover panel evaluates deadlines natively while WebKit is hidden.
final class MenuBarController: NSObject {
    let item: NSStatusItem
    let panel = FocusPopoverView()
    private(set) var hoverWindow: MenuBarHoverWindow!
    var onAction: ((String) -> Void)?
    var dark = false { didSet { refresh() } }
    private var schedule: FocusSchedule?
    private var taskTitle = ""
    private var timer: Timer?
    private var awaitingPauseAcknowledgement = false
    // AppKit may omit status-button tracking events while this app is inactive.
    // Sampling the public pointer position also covers that background-app case.
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }
    private var lastRefresh = Date.distantPast
    private var hoverDismissed = false
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var actionTimeout: DispatchWorkItem?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var insideItem = false
    private var insidePanel = false
    private(set) var busy = false
    private(set) var actionFailed = false
    var isShown: Bool { hoverWindow.isVisible }

    init(target: AnyObject, action: Selector) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        // Keep a stable identity so macOS remembers where the user places this item.
        item.autosaveName = "FocusOnTimer"
        item.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Focus On")
        item.button?.image?.isTemplate = true
        item.button?.imagePosition = .imageOnly
        item.button?.target = target
        item.button?.action = action
        hoverWindow = MenuBarHoverWindow(content: panel)
        panel.onToggle = { [weak self] in
            guard let self else { return }
            self.performAction(self.snapshot.running ? "pause" : "toggle")
        }
        panel.onReset = { [weak self] in self?.performAction("reset") }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, self.isShown else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.close(); return nil }
            } else { self.dismissForOutsideClick() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissForOutsideClick()
        }
        refresh()
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.samplePointer()
            let now = Date()
            if now.timeIntervalSince(self.lastRefresh) >= 0.25 {
                self.lastRefresh = now
                self.refresh(at: now.timeIntervalSince1970)
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func synchronize(_ schedule: FocusSchedule, taskTitle: String) {
        guard schedule.isValid else { return }
        if awaitingPauseAcknowledgement {
            guard !schedule.running else { return }
            awaitingPauseAcknowledgement = false
        }
        self.schedule = schedule
        self.taskTitle = taskTitle
        busy = false
        actionFailed = false
        actionTimeout?.cancel()
        refresh()
    }

    func pause() {
        guard let schedule, schedule.running else { return }
        awaitingPauseAcknowledgement = true
        let elapsed = min(schedule.phases.reduce(0) { $0 + $1.seconds },
                          schedule.elapsed + max(0, Date().timeIntervalSince1970 - (schedule.startedAt ?? Date().timeIntervalSince1970)))
        self.schedule = FocusSchedule(running: false, startedAt: nil, elapsed: elapsed,
                                      phases: schedule.phases, monitoring: schedule.monitoring, sessionId: schedule.sessionId)
        refresh()
    }

    func refresh(at now: Double = Date().timeIntervalSince1970) {
        let state = MenuBarSnapshot.make(schedule: schedule, taskTitle: taskTitle, at: now)
        let text = Self.summary(schedule: schedule, taskTitle: taskTitle, at: now)
        item.button?.setAccessibilityLabel("Focus On，\(text)")
        item.button?.setAccessibilityHelp("悬停控制计时；点击显示专注窗口")
        hoverWindow.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        panel.render(state, dark: dark, busy: busy)
        if actionFailed { panel.statusLabel.stringValue = "未响应，请重试" }
    }

    var snapshot: MenuBarSnapshot { MenuBarSnapshot.make(schedule: schedule, taskTitle: taskTitle, at: Date().timeIntervalSince1970) }
    var tooltipText: String { Self.summary(schedule: schedule, taskTitle: taskTitle, at: Date().timeIntervalSince1970) }

    var itemScreenRect: NSRect? {
        guard item.isVisible, let button = item.button, let window = button.window,
              window.isVisible, !button.bounds.isEmpty else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
    var panelScreenRect: NSRect? { isShown ? hoverWindow.frame : nil }

    private func samplePointer() {
        let mouse = pointerLocation()
        insideItem = itemScreenRect?.contains(mouse) == true
        insidePanel = panelScreenRect?.contains(mouse) == true
        if insideItem || insidePanel {
            closeWork?.cancel(); closeWork = nil
            guard !isShown, !hoverDismissed, openWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.openWork = nil
                // Check again: a fast pass must not open the panel between samples.
                guard self.itemScreenRect?.contains(self.pointerLocation()) == true, !self.hoverDismissed else { return }
                self.show()
            }
            openWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        } else {
            hoverDismissed = false
            openWork?.cancel(); openWork = nil
            guard isShown, closeWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.closeWork = nil
                let point = self.pointerLocation()
                guard self.itemScreenRect?.contains(point) != true, self.panelScreenRect?.contains(point) != true else { return }
                self.close()
            }
            closeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }
    func show() {
        guard !isShown, let anchor = itemScreenRect,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }) else { return }
        refresh()
        hoverWindow.show(anchor: anchor, screen: screen)
    }
    func close() {
        openWork?.cancel(); closeWork?.cancel()
        openWork = nil; closeWork = nil
        hoverDismissed = true
        insideItem = false; insidePanel = false
        hoverWindow.orderOut(nil)
    }
    private func dismissForOutsideClick() {
        guard isShown else { return }
        let mouse = NSEvent.mouseLocation
        if panel.window?.frame.contains(mouse) == true { return }
        if let button = item.button, let window = button.window,
           window.convertToScreen(button.convert(button.bounds, to: nil)).contains(mouse) { return }
        close()
    }
    private func performAction(_ action: String) {
        guard !busy, action != "reset" || snapshot.hasSession else { return }
        busy = true
        actionFailed = false
        refresh()
        // A timeout stays local to the hover UI. It must never activate the app
        // or reopen its main window after the user has moved away.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.busy else { return }
            self.busy = false; self.actionFailed = true; self.refresh()
        }
        actionTimeout?.cancel(); actionTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        onAction?(action)
    }

    static func summary(schedule: FocusSchedule?, taskTitle: String, at now: Double) -> String {
        let task = taskTitle.isEmpty ? "未设置任务" : taskTitle
        guard let schedule, schedule.isValid else { return "Focus On · 尚未开始\n\(task)" }
        var elapsed = schedule.elapsed
        if schedule.running, let startedAt = schedule.startedAt { elapsed += max(0, now - startedAt) }
        for phase in schedule.phases {
            if elapsed < phase.seconds {
                let remaining = Int(ceil(phase.seconds - elapsed))
                let time = String(format: "%02d:%02d", remaining / 60, remaining % 60)
                let state = schedule.sessionId == nil ? "尚未开始" : schedule.running ? (phase.kind == "break" ? "休息中" : "专注中") : "已暂停"
                return "\(state) · 剩余 \(time)\n\(task)"
            }
            elapsed -= phase.seconds
        }
        return "本次专注已完成 · 00:00\n\(task)"
    }

    deinit {
        timer?.invalidate()
        openWork?.cancel(); closeWork?.cancel(); actionTimeout?.cancel()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        NSStatusBar.system.removeStatusItem(item)
    }
}
