import AppKit
import FocusCore

extension AppDelegate {
    @MainActor
    func checkMenuBarPopover(directory: String, require: (Bool, String) throws -> Void) async throws {
        let phases = [FocusPhase(kind: "focus", seconds: 900), FocusPhase(kind: "break", seconds: 300), FocusPhase(kind: "focus", seconds: 900)]
        let sample = FocusSchedule(running: true, startedAt: 100, elapsed: 0, phases: phases, monitoring: false, sessionId: "panel-check")
        let rest = MenuBarSnapshot.make(schedule: sample, taskTitle: "分段任务", at: 1000)
        let second = MenuBarSnapshot.make(schedule: sample, taskTitle: "分段任务", at: 1300)
        let done = MenuBarSnapshot.make(schedule: sample, taskTitle: "分段任务", at: 2200)
        try require(rest.isBreak && rest.remaining == 300 && rest.round == 1 && rest.rounds == 2 &&
                    second.round == 2 && second.remaining == 900 && !second.isBreak &&
                    done.finished && !done.running && done.progress == 0,
                    "Popover state follows break, round transitions and completion without web timer ticks")

        try require(menuBar.item.button?.image != nil && menuBar.item.button?.title.isEmpty == true &&
                    menuBar.item.length == NSStatusItem.squareLength, "Menu bar displays only the timer icon, never countdown text")
        let livePointer = menuBar.pointerLocation
        var pointer = NSPoint(x: -100_000, y: -100_000)
        menuBar.pointerLocation = { pointer }
        defer { menuBar.pointerLocation = livePointer }
        menuBar.close()
        try await Task.sleep(nanoseconds: 150_000_000)
        minimizeToMenuBar()
        NSApp.deactivate()
        try await Task.sleep(nanoseconds: 150_000_000)
        let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let keyWindow = NSApp.keyWindow
        let hover = menuBar.hoverWindow!
        try require(hover.frame.size == NSSize(width: 272, height: 224) &&
                    hover.styleMask.contains(.nonactivatingPanel) && !hover.canBecomeKey && !hover.canBecomeMain &&
                    !hover.hidesOnDeactivate && hover.collectionBehavior.contains(.canJoinAllSpaces) &&
                    hover.collectionBehavior.contains(.fullScreenAuxiliary),
                    "Compact hover window is nonactivating and available above other apps and full-screen Spaces")
        try require(menuBar.panel.toggleButton.acceptsFirstMouse(for: nil) && !menuBar.panel.toggleButton.needsPanelToBecomeKey,
                    "Hover controls accept clicks without activating Focus On")
        let screenRect = NSScreen.main!.visibleFrame
        let backdrop = NSPanel(contentRect: screenRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        backdrop.isReleasedWhenClosed = false
        backdrop.hidesOnDeactivate = false
        backdrop.backgroundColor = .windowBackgroundColor
        backdrop.level = .normal
        backdrop.orderFrontRegardless()
        defer { backdrop.orderOut(nil) }
        guard let iconRect = menuBar.itemScreenRect else {
            try require(false, "Status item has a visible screen rectangle for hover detection")
            return
        }
        try require(NSScreen.screens.contains { $0.frame.intersects(iconRect) }, "Status item hover uses on-screen coordinates")
        pointer = NSPoint(x: iconRect.midX, y: iconRect.midY)
        try await Task.sleep(nanoseconds: 350_000_000)
        try require(menuBar.isShown && !window.isVisible, "Production pointer sampling opens the popover after the app is deactivated, without mouse-enter callbacks")
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let hoverIndex = windows.firstIndex { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == hover.windowNumber }
        let backdropIndex = windows.firstIndex { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == backdrop.windowNumber }
        try require(hoverIndex != nil && backdropIndex != nil && hoverIndex! < backdropIndex! && hover.level.rawValue > backdrop.level.rawValue,
                    "WindowServer orders the hover surface above a normal foreground window")
        try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == foregroundPID && NSApp.keyWindow === keyWindow,
                    "Opening the hover surface preserves the foreground app and keyboard focus")
        backdrop.orderOut(nil)
        guard let panelRect = menuBar.panelScreenRect else {
            try require(false, "Open popover has a screen rectangle for pointer handoff")
            return
        }
        pointer = NSPoint(x: -100_000, y: -100_000)
        try await Task.sleep(nanoseconds: 80_000_000)
        pointer = NSPoint(x: panelRect.midX, y: panelRect.midY)
        try await Task.sleep(nanoseconds: 350_000_000)
        try require(menuBar.isShown, "Crossing the icon-to-panel gap cancels dismissal and keeps controls available")
        menuBar.panel.toggleButton.performClick(nil)
        try await Task.sleep(nanoseconds: 350_000_000)
        try require(manager.schedule?.running == true && menuBar.snapshot.running && !window.isVisible && !menuBar.busy,
                    "Popover resume reaches the persisted web session while the main window stays hidden")
        menuBar.panel.toggleButton.performClick(nil)
        try await Task.sleep(nanoseconds: 350_000_000)
        try require(manager.schedule?.running == false && menuBar.panel.statusLabel.stringValue == "已暂停",
                    "Popover pause stops monitoring and updates its native status")
        menuBar.panel.resetButton.performClick(nil)
        try await Task.sleep(nanoseconds: 350_000_000)
        let reset = try await webView.evaluateJavaScript("JSON.parse(localStorage.getItem('focus-on.v1')).session === null") as? Bool
        try require(reset == true && menuBar.snapshot.remaining == 1500 && menuBar.snapshot.round == 1 &&
                    menuBar.snapshot.progress == 0 && !menuBar.panel.resetButton.isEnabled && menuBar.panel.toggleButton.title == "开始专注",
                    "Reset clears the entire session and returns to the first round without deleting the task")

        // Enter a real break through the bundled UI, then click the native action.
        _ = try await webView.evaluateJavaScript("""
        (() => {
          const slider = document.querySelector('[role=slider]');
          slider.dispatchEvent(new KeyboardEvent('keydown', {key: 'PageUp', bubbles: true}));
        })()
        """)
        try await Task.sleep(nanoseconds: 80_000_000)
        _ = try await webView.evaluateJavaScript("document.querySelector('[role=slider]').dispatchEvent(new KeyboardEvent('keydown', {key: 'PageUp', bubbles: true}))")
        try await Task.sleep(nanoseconds: 80_000_000)
        _ = try await webView.evaluateJavaScript("window.smokeOriginalNow = Date.now; Date.now = () => window.smokeOriginalNow() - 900000; document.querySelector('.start-button').click()")
        try await Task.sleep(nanoseconds: 100_000_000)
        _ = try await webView.evaluateJavaScript("Date.now = window.smokeOriginalNow; delete window.smokeOriginalNow")
        try await Task.sleep(nanoseconds: 350_000_000)
        menuBar.refresh()
        try require(menuBar.snapshot.isBreak && menuBar.panel.toggleButton.title == "跳过休息" &&
                    menuBar.panel.resetButton.isHidden && menuBar.panel.durationLabel.stringValue == "/ 05:00",
                    "During rest the native popover shows break duration and only Skip Rest")
        menuBar.panel.toggleButton.performClick(nil)
        try await Task.sleep(nanoseconds: 350_000_000)
        try require(manager.schedule?.elapsed == 1200 && manager.schedule?.running == true &&
                    !menuBar.snapshot.isBreak && menuBar.snapshot.round == 2 && !window.isVisible,
                    "Native Skip Rest advances the persisted session to the next focus without opening the window")
        menuBar.panel.resetButton.performClick(nil)
        try await Task.sleep(nanoseconds: 150_000_000)

        for theme in ["dark", "light"] {
            _ = try await webView.evaluateJavaScript("document.querySelector('input[name=theme][value=\(theme)]').click()")
            try await Task.sleep(nanoseconds: 100_000_000)
            try require(menuBar.dark == (theme == "dark"), "Popover follows the app's \(theme) theme through the native bridge")
            let palette = FocusPopoverPalette(dark: theme == "dark")
            let cssRest = try await webView.evaluateJavaScript("getComputedStyle(document.documentElement).getPropertyValue('--orange').trim()") as? String
            let nativeRest = palette.rest.usingColorSpace(.sRGB)!
            let nativeHex = String(format: "#%02x%02x%02x", Int(round(nativeRest.redComponent * 255)), Int(round(nativeRest.greenComponent * 255)), Int(round(nativeRest.blueComponent * 255)))
            try require(cssRest == nativeHex, "Native rest palette exactly matches the current \(theme) --orange token")
            menuBar.panel.render(rest, dark: theme == "dark", busy: false)
            try require(menuBar.panel.toggleButton.layer?.backgroundColor == palette.rest.cgColor &&
                        menuBar.panel.toggleButton.title == "跳过休息" && menuBar.panel.resetButton.isHidden,
                        "Rest uses the themed accent even while running and hides Reset")
            try savePopoverImage(directory: directory, name: "popover-\(theme)-rest")
            let screenshotState = MenuBarSnapshot(title: "整理周末的出行清单", status: "专注中", remaining: 1153, duration: 1500,
                round: 2, rounds: 4, running: true, hasSession: true, finished: false, isBreak: false, progress: 1153.0 / 1500)
            menuBar.panel.render(screenshotState, dark: theme == "dark", busy: false)
            try savePopoverImage(directory: directory, name: "popover-\(theme)-running")
            var paused = screenshotState
            paused.running = false; paused.status = "已暂停"
            menuBar.panel.render(paused, dark: theme == "dark", busy: false)
            try savePopoverImage(directory: directory, name: "popover-\(theme)-paused")
        }
        menuBar.refresh()
        pointer = NSPoint(x: -100_000, y: -100_000)
        try await Task.sleep(nanoseconds: 500_000_000)
        try require(!menuBar.isShown, "Leaving both icon and panel closes the popover after the grace period")
        try require(!window.isVisible && NSWorkspace.shared.frontmostApplication?.processIdentifier == foregroundPID,
                    "Pointer exit hides only the hover surface and never raises the main app")
        pointer = NSPoint(x: iconRect.midX, y: iconRect.midY)
        try await Task.sleep(nanoseconds: 100_000_000)
        pointer = NSPoint(x: -100_000, y: -100_000)
        try await Task.sleep(nanoseconds: 250_000_000)
        try require(!menuBar.isShown, "Passing quickly over the menu item does not flash a popover")
        pointer = NSPoint(x: iconRect.midX, y: iconRect.midY)
        try await Task.sleep(nanoseconds: 350_000_000)
        try require(menuBar.isShown, "Returning to the icon opens the panel again")
        menuBar.close()
        try await Task.sleep(nanoseconds: 350_000_000)
        try require(!menuBar.isShown, "Explicit dismissal does not reopen while the pointer remains on the icon")
        // Exercise the old three-second fallback after leaving the surface.
        // A slow/unavailable web process must not open the main app in the background.
        let actionHandler = menuBar.onAction
        menuBar.onAction = nil
        menuBar.panel.toggleButton.performClick(nil)
        try require(menuBar.busy, "Unacknowledged panel action waits without submitting duplicate actions")
        pointer = NSPoint(x: -100_000, y: -100_000)
        try await Task.sleep(nanoseconds: 3_600_000_000)
        menuBar.onAction = actionHandler
        // Other apps (including the test browser) can exit during the timeout.
        // The contract is that Focus On never activates itself or opens a window.
        try require(menuBar.actionFailed && !menuBar.busy && !menuBar.isShown && !window.isVisible &&
                    NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                    "An action timeout after dismissal never activates or opens Focus On")
        menuBar.close()
        showWindow()
    }

    private func savePopoverImage(directory: String, name: String) throws {
        let view = menuBar.panel
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: rep) }
        if let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }
}
