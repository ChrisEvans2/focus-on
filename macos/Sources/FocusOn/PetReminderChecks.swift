import AppKit

@MainActor
func checkPetReminder(directory: String, require: (Bool, String) throws -> Void) async throws {
    let reminder = ReminderController()
    defer { reminder.hide(immediate: true) }
    let keyWindow = NSApp.keyWindow
    let mainWindow = NSApp.mainWindow
    reminder.theme = .dark
    reminder.show()
    let original = reminder.panels
    try require(!original.isEmpty && original.count == NSScreen.screens.count,
                "One compact pet appears on each connected display")
    try require(zip(original, NSScreen.screens).allSatisfy { panel, screen in
        abs(panel.frame.midX - screen.frame.midX) < 1 && abs(panel.frame.midY - screen.frame.midY) < 1 &&
        panel.frame.size == PetCompanionView.canvasSize && panel.ignoresMouseEvents &&
        !panel.canBecomeMain && !panel.canBecomeKey && panel.styleMask.contains(.nonactivatingPanel) &&
        panel.collectionBehavior.contains(.canJoinAllSpaces) &&
        panel.contentView?.hitTest(NSPoint(x: panel.frame.width / 2, y: panel.frame.height / 2)) == nil
    }, "Pets are centered, compact, click-through and excluded from keyboard focus")
    try require(original.allSatisfy { ($0.contentView as? PetCompanionView)?.theme == .dark },
                "New pets inherit the selected dark theme")
    reminder.theme = .light
    try require(reminder.panels == original && original.allSatisfy {
        ($0.contentView as? PetCompanionView)?.theme == .light && $0.contentView?.needsDisplay == true
    }, "Theme changes repaint every existing pet without replacing its panel")
    reminder.show()
    try require(reminder.panels == original, "Repeated distraction samples do not duplicate panels or restart animation")
    try await Task.sleep(nanoseconds: 350_000_000)
    try require(NSApp.keyWindow === keyWindow && NSApp.mainWindow === mainWindow,
                "Showing a pet leaves the existing key and main windows unchanged")
    let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    try require(reduced ? !reminder.isAnimating : reminder.isAnimating &&
                (original.first?.contentView as? PetCompanionView)?.time ?? 0 > 0,
                "Animation advances while visible; reduced motion keeps it static without a timer")

    let poses = stride(from: 0.0, to: 12, by: 0.04).map { PetPose.at($0, reducedMotion: false) }
    try require(poses.contains { $0.x < -12 } && poses.contains { $0.x > 12 } &&
                poses.contains { $0.y < -9 } && poses.contains { $0.y > 9 } &&
                poses.contains { $0.openness < 0.2 },
                "The pet looks left, right, up and down and blinks during its loop")
    let start = PetPose.at(0, reducedMotion: false), end = PetPose.at(12, reducedMotion: false)
    try require(start.x == end.x && start.y == end.y && start.openness == end.openness &&
                stride(from: 0.0, to: 12, by: 0.1).allSatisfy {
                    let pose = PetPose.at($0, reducedMotion: true)
                    return pose.x == 0 && pose.y == 0 && pose.openness == 1
                }, "Loop joins at idle and reduced motion suppresses all eye movement")

    // Render the actual native view, at deterministic phases, for visual review.
    let size = PetCompanionView.canvasSize
    let sheet = NSImage(size: NSSize(width: size.width * 6, height: size.height))
    sheet.lockFocus()
    NSColor(srgbRed: 0.976, green: 0.969, blue: 0.957, alpha: 1).setFill()
    NSRect(origin: .zero, size: sheet.size).fill()
    for (index, time) in [0.0, 2.0, 3.6, 6.4, 7.9, 0.84].enumerated() {
        let view = PetCompanionView(frame: NSRect(origin: .zero, size: PetCompanionView.canvasSize))
        view.time = time
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        bitmap.draw(in: NSRect(x: CGFloat(index) * size.width, y: 0, width: size.width, height: size.height))
    }
    sheet.unlockFocus()
    if let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
       let png = bitmap.representation(using: .png, properties: [:]) {
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("pet-states.png"))
    }

    reminder.hide()
    try require(!reminder.visible && !reminder.isAnimating, "Return stops the animation timer immediately")
    reminder.theme = .dark
    reminder.show()
    let replacement = reminder.panels
    try require(replacement.allSatisfy { ($0.contentView as? PetCompanionView)?.theme == .dark },
                "Pets retain the selected theme when shown again")
    try await Task.sleep(nanoseconds: 400_000_000)
    try require(reminder.visible && reminder.panels == replacement && replacement.allSatisfy(\.isVisible) &&
                original.allSatisfy { !$0.isVisible }, "An old fade completion cannot dismiss a newer reminder")
    reminder.hide()
    try await Task.sleep(nanoseconds: 400_000_000)
    try require(reminder.panels.isEmpty && replacement.allSatisfy { !$0.isVisible } && !reminder.isAnimating,
                "Return finishes fading and releases every pet panel")
    reminder.show()
    let stopped = reminder.panels
    reminder.hide(immediate: true)
    try require(!reminder.visible && reminder.panels.isEmpty && stopped.allSatisfy { !$0.isVisible } && !reminder.isAnimating,
                "Pause or shutdown removes pets and stops animation without waiting for a fade")
}
