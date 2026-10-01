import AppKit
import FocusCore

@MainActor
func checkPhaseReminder(directory: String, require: (Bool, String) throws -> Void) async throws {
    let spriteURL = Bundle.module.url(forResource: "phase-peek", withExtension: "png")!
    let bitmap = NSBitmapImageRep(data: try Data(contentsOf: spriteURL))!
    try require(spriteURL.path.hasPrefix(Bundle.main.bundleURL.path + "/") && bitmap.hasAlpha &&
                bitmap.colorAt(x: 0, y: 0)?.alphaComponent == 0 &&
                PhaseReminderView.spriteFrames.allSatisfy { NSRect(origin: .zero, size: PhaseReminderView.sprite.size).contains($0) } &&
                PhaseReminderView.spriteFrames.count == 4,
                "The generated transparent peek atlas loads from inside the shipped app with all four theme/expression frames intact")
    var now = 100.0
    let manager = FocusSessionManager(epochTime: { now }, automaticTicks: false)
    defer { manager.shutdown() }
    let phases = [FocusPhase(kind: "focus", seconds: 900), FocusPhase(kind: "break", seconds: 300), FocusPhase(kind: "focus", seconds: 900)]
    let schedule = FocusSchedule(running: true, startedAt: 100, elapsed: 0, phases: phases, monitoring: false, sessionId: "phase-check")
    manager.synchronize(schedule)
    try require(!manager.phaseReminder.visible, "Starting a session does not show a phase-end reminder")
    now = 1000; manager.tick()
    let reminder = manager.phaseReminder
    let original = reminder.panels
    try require(reminder.visible && reminder.message == "专注结束啦，休息 5 分钟。" && !manager.reminder.visible,
                "Focus deadline shows a text-only rest reminder even with camera monitoring off")
    try require(!original.isEmpty && zip(original, NSScreen.screens).allSatisfy { panel, screen in
        abs(panel.frame.maxX - screen.visibleFrame.maxX) < 1 && panel.frame.size == PhaseReminderView.reminderSize &&
        panel.ignoresMouseEvents && !panel.canBecomeKey && !panel.canBecomeMain &&
        panel.contentView is PhaseReminderView && panel.contentView?.subviews.isEmpty == true
    }, "Phase pets sit inside the right screen edge, have no buttons and cannot take keyboard or mouse focus")
    manager.tick(); manager.synchronize(schedule)
    try require(reminder.panels == original, "Repeated ticks and syncs do not duplicate phase reminders or restart their lifetime")
    now = 1300; manager.tick()
    try require(reminder.message == "休息结束啦，继续专注吧。", "Break deadline updates the pet text for the next focus")
    now = 2200
    manager.synchronize(FocusSchedule(running: false, startedAt: nil, elapsed: 2100, phases: phases, monitoring: false, sessionId: "phase-check"))
    try require(reminder.visible && reminder.message == "本次专注完成啦，辛苦了。",
                "Completion arriving from the web before a native tick still shows the final reminder")
    manager.stop()
    try require(!reminder.visible && !reminder.isAnimating, "Stopping or resetting clears phase reminders and animation")
    now = 100; manager.synchronize(schedule)
    now = 1000; manager.tick()
    manager.synchronize(FocusSchedule(running: false, startedAt: nil, elapsed: 900, phases: phases, monitoring: false, sessionId: "phase-check"))
    try require(!reminder.visible, "Pausing a break dismisses its phase reminder")

    let smile = PhasePetPose.at(1.5, reducedMotion: false)
    let wink = PhasePetPose.at(2.625, reducedMotion: false)
    let next = PhasePetPose.at(4.5, reducedMotion: false)
    let reduced = PhasePetPose.at(2.625, reducedMotion: true)
    let bounds = NSRect(origin: .zero, size: PhaseReminderView.reminderSize)
    let visiblePet = PhaseReminderView.petRect(in: bounds, pose: smile)
    let hiddenPet = PhaseReminderView.petRect(in: bounds, pose: PhasePetPose.at(0, reducedMotion: false))
    try require(visiblePet.height == 220 && visiblePet.intersection(bounds).width == 160 &&
                visiblePet.maxX > bounds.maxX && hiddenPet.minX >= bounds.maxX,
                "The larger 160 by 220 point peek enters from outside and stays flush with the clipping edge")
    try require(smile.wink == 0 && wink.wink > 0.99 && abs(smile.bob - next.bob) < 0.001 &&
                reduced.entrance == 1 && reduced.wink == 0 && reduced.bob == 0,
                "The pet loops smile and wink continuously; reduced motion gives a settled static smile")
    for theme in [PetTheme.light, .dark] {
        let size = PhaseReminderView.reminderSize
        let sheet = NSImage(size: NSSize(width: size.width * 3, height: size.height))
        sheet.lockFocus()
        FocusPopoverPalette(dark: theme == .dark).canvas.setFill()
        NSRect(origin: .zero, size: sheet.size).fill()
        for (index, time) in [0.15, 1.5, 2.625].enumerated() {
            let view = PhaseReminderView(frame: NSRect(origin: .zero, size: size), message: "专注结束啦，休息 5 分钟。")
            view.theme = theme; view.time = time
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                bitmap.draw(in: NSRect(x: CGFloat(index) * size.width, y: 0, width: size.width, height: size.height))
            }
        }
        sheet.unlockFocus()
        if let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("phase-pet-\(theme.rawValue).png"))
        }
    }
    reminder.show(message: "休息结束啦，继续专注吧。", duration: 0.1)
    try await Task.sleep(nanoseconds: 450_000_000)
    try require(!reminder.visible && reminder.panels.isEmpty && !reminder.isAnimating,
                "Text-only reminders dismiss automatically and release their panels and timers")
}
