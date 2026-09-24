import FocusVision
import AppKit
import WebKit
import FocusCore
import CoreVideo

extension AppDelegate {
    func runSmokeTest(directory: String) {
        Task { @MainActor in
            var checks: [String] = []
            func require(_ condition: Bool, _ name: String) throws {
                guard condition else { throw NSError(domain: "FocusOnSmokeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
                checks.append(name)
            }
            do {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                let count = try await webView.evaluateJavaScript("document.querySelectorAll('.start-button').length") as? Int
                try require(count == 1, "Bundled React UI loads in WKWebView without a server")
                _ = try await webView.evaluateJavaScript("document.querySelector('.settings-button').click()")
                try await Task.sleep(nanoseconds: 200_000_000)
                _ = try await webView.evaluateJavaScript("document.querySelector('.camera-settings input').click()")
                try await Task.sleep(nanoseconds: 200_000_000)
                let disabled = try await webView.evaluateJavaScript("localStorage.getItem('focus-on.camera')") as? String
                try require(disabled == "off", "Camera preference persists on the bundled origin")
                _ = try await webView.evaluateJavaScript("""
                (() => {
                  document.querySelector('dialog').close();
                  const input = document.querySelector('#task-input');
                  Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, '菜单栏专注任务');
                  input.dispatchEvent(new Event('input', { bubbles: true }));
                })()
                """)
                try await Task.sleep(nanoseconds: 100_000_000)
                _ = try await webView.evaluateJavaScript("document.querySelector('.start-button').click()")
                try await Task.sleep(nanoseconds: 350_000_000)
                try require(manager.schedule?.running == true && manager.schedule?.monitoring == false, "Start reaches native schedule with camera disabled")
                let remaining = try await webView.evaluateJavaScript("document.querySelector('.dial-time').textContent") as? String
                try require(remaining != nil, "Running countdown renders")
                try require(menuBar.item.isVisible && menuBar.tooltipText.contains("菜单栏专注任务") == true,
                            "Clicking Start submits the draft and synchronizes its title to the native menu bar")
                _ = try await webView.evaluateJavaScript("document.querySelector('.minimize-button').click()")
                try await Task.sleep(nanoseconds: 150_000_000)
                let tooltipBefore = menuBar.tooltipText
                try require(!window.isVisible && manager.schedule?.running == true,
                            "Header button minimizes to the menu bar without pausing the native schedule")
                try await Task.sleep(nanoseconds: 1_300_000_000)
                menuBar.refresh()
                try require(menuBar.tooltipText != tooltipBefore && menuBar.tooltipText.contains("专注中 · 剩余") == true,
                            "Native menu-bar countdown advances while the main window is hidden")
                menuBar.item.button?.performClick(nil)
                try require(window.isVisible && manager.schedule?.running == true,
                            "Clicking the menu-bar icon restores the running window")
                let schedule = FocusSchedule(running: true, startedAt: 100, elapsed: 0,
                    phases: [FocusPhase(kind: "focus", seconds: 900), FocusPhase(kind: "break", seconds: 300), FocusPhase(kind: "focus", seconds: 900)],
                    monitoring: false, sessionId: "menu-bar-check")
                try require(MenuBarController.summary(schedule: schedule, taskTitle: "任务", at: 101) == "专注中 · 剩余 14:59\n任务" &&
                            MenuBarController.summary(schedule: schedule, taskTitle: "任务", at: 1000) == "休息中 · 剩余 05:00\n任务" &&
                            MenuBarController.summary(schedule: schedule, taskTitle: "任务", at: 2200) == "本次专注已完成 · 00:00\n任务",
                            "Menu-bar tooltip follows focus, break and completion deadlines without WebKit ticks")
                pause()
                try await Task.sleep(nanoseconds: 350_000_000)
                let paused = try await webView.evaluateJavaScript("JSON.parse(localStorage.getItem('focus-on.v1')).session.startedAt === null") as? Bool
                try require(paused == true && manager.schedule?.running == false, "Native pause updates and persists the React timer")
                try require(menuBar.tooltipText.contains("已暂停") == true, "Menu-bar tooltip reflects native pause")
                try await checkMenuBarPopover(directory: directory, require: require)
                _ = try await webView.evaluateJavaScript("document.querySelector('.complete-task').click()")
                try await Task.sleep(nanoseconds: 100_000_000)
                try require(menuBar.tooltipText.contains("未设置任务") == true, "Completing a task clears the menu-bar task title")
                let image = try await webView.takeSnapshot(configuration: nil)
                if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                    try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("native-window.png"))
                }
                _ = try await webView.evaluateJavaScript("window.webkit.messageHandlers.focusOn.postMessage({command: 'eyeTest'}); true")
                try await Task.sleep(nanoseconds: 100_000_000)
                try require(eyeDebug.window?.isVisible == true, "Eye test opens from the native bridge without starting capture")
                let outline = [EyePoint(x: 0, y: 0), EyePoint(x: 10, y: 6), EyePoint(x: 30, y: 6), EyePoint(x: 40, y: 0), EyePoint(x: 30, y: -6), EyePoint(x: 10, y: -6)]
                let measured = EyeGeometry.measure(contour: outline, pupil: EyePoint(x: 20, y: -2))!
                eyeDebug.render(FaceState(faceDetected: true, pitch: -4.2, yaw: 2.1, roll: 0, eyes: EyePair(left: measured, right: measured)), at: 1)
                if let content = eyeDebug.window?.contentView,
                   let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                    content.layoutSubtreeIfNeeded()
                    content.effectiveAppearance.performAsCurrentDrawingAppearance { content.cacheDisplay(in: content.bounds, to: rep) }
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("eye-test.png"))
                    }
                }
                eyeDebug.window?.performClose(nil)
                try require(eyeDebug.window?.isVisible == false, "Eye test closes and releases its capture lifecycle")
                var buffer: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
                if let buffer {
                    CVPixelBufferLockBaseAddress(buffer, [])
                    memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetDataSize(buffer))
                    CVPixelBufferUnlockBaseAddress(buffer, [])
                    let analyzer = VisionAnalyzer()
                    try require(!analyzer.analyze(buffer, orientation: .up).valid, "Dark frames are unavailable, never away")
                    CVPixelBufferLockBaseAddress(buffer, [])
                    memset(CVPixelBufferGetBaseAddress(buffer), 220, CVPixelBufferGetDataSize(buffer))
                    CVPixelBufferUnlockBaseAddress(buffer, [])
                    let empty = analyzer.analyze(buffer, orientation: .up)
                    try require(empty.valid && !empty.faceDetected, "Actual Vision inference distinguishes a lit empty frame")
                } else { try require(false, "Allocate Vision test frame") }
                manager.engine.reset()
                for i in 0...20 { manager.consume(FaceState(faceDetected: true, pitch: 31, yaw: 0, roll: 0), at: Double(i) * 0.1) }
                try require(manager.engine.baselinePitch == nil && !manager.reminder.visible, "Startup glance is observed without accepting a baseline or showing a pet")
                for i in 21...65 { manager.consume(FaceState(faceDetected: true, pitch: 0, yaw: 0, roll: 0), at: Double(i) * 0.1) }
                try require(manager.engine.state == .focused && manager.engine.baselinePitch == 0, "Native controller adapts automatically after an initial downward glance")
                _ = try await webView.evaluateJavaScript("window.webkit.messageHandlers.focusOn.postMessage({command: 'monitorDiagnostics'}); true")
                try await Task.sleep(nanoseconds: 100_000_000)
                try require(monitorDiagnostics.window?.isVisible == true && manager.engine.baselinePitch == 0 && !eyeDebug.isRunning,
                            "Monitor diagnostics opens without resetting production evidence or starting eye capture")
                // The smoke schedule is deliberately paused (no real webcam). Its idle
                // timer clears diagnostics, so deliver the next synthetic frame after await.
                manager.consume(FaceState(faceDetected: true, pitch: 0, yaw: 0, faceCount: 1, confidence: 0.95), at: 6.6)
                try require(manager.diagnosticText.contains("头部偏离未超过阈值"), "Diagnostic uses the live production baseline and explains why no pet appears")
                if let content = monitorDiagnostics.window?.contentView,
                   let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                    content.layoutSubtreeIfNeeded(); content.cacheDisplay(in: content.bounds, to: rep)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("monitor-diagnostics.png"))
                    }
                }
                monitorDiagnostics.window?.performClose(nil)
                for i in 67...155 { manager.consume(FaceState(faceDetected: true, pitch: 0, yaw: 55), at: Double(i) * 0.1) }
                try require(manager.reminder.visible && !manager.reminder.panels.isEmpty, "Sustained head turn displays real AppKit pet panels")
                try require(manager.reminder.panels.allSatisfy { $0.ignoresMouseEvents && !$0.canBecomeKey && $0.collectionBehavior.contains(.fullScreenAuxiliary) }, "Pet is click-through, nonactivating, and configured for full-screen Spaces")
                if let view = manager.reminder.panels.first?.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    (view as? PetCompanionView)?.time = 1
                    view.cacheDisplay(in: view.bounds, to: rep)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("pet-overlay.png"))
                    }
                }
                for i in 156...190 { manager.consume(FaceState(faceDetected: true, pitch: 0, yaw: 0), at: Double(i) * 0.1) }
                try require(!manager.reminder.visible && manager.engine.state == .focused, "Stable return dismisses pet automatically")
                manager.engine.reset()
                let centerEye = EyeGeometry.measure(contour: outline, pupil: EyePoint(x: 20, y: 0))!
                let downEye = EyeGeometry.measure(contour: outline, pupil: EyePoint(x: 20, y: -2.4))!
                func gazeSample(_ eye: EyeMeasurement) -> FaceState {
                    FaceState(faceDetected: true, pitch: 13.7, yaw: 7.9, roll: 0, eyes: EyePair(left: eye, right: eye), faceCount: 1, confidence: 0.95)
                }
                for i in 0...65 { manager.consume(gazeSample(centerEye), at: Double(i) / 10) }
                try require(manager.engine.gaze.calibrated, "Production controller automatically calibrates both pupils with the head baseline")
                for i in 66...195 { manager.consume(gazeSample(downEye), at: Double(i) / 10) }
                try require(manager.reminder.visible && manager.engine.reminderSource == .gaze,
                            "Eye-only downward deviation displays real pet panels even with an unchanged head")
                showMonitorDiagnostics()
                if let content = monitorDiagnostics.window?.contentView,
                   let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                    content.layoutSubtreeIfNeeded(); content.cacheDisplay(in: content.bounds, to: rep)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("monitor-diagnostics.png"))
                    }
                }
                monitorDiagnostics.window?.performClose(nil)
                for i in 196...230 { manager.consume(gazeSample(centerEye), at: Double(i) / 10) }
                try require(!manager.reminder.visible && manager.engine.state == .focused,
                            "Combined head and gaze return dismisses the eye-triggered pet")
                manager.stop()
                try require(manager.diagnosticText == "摄像头已关闭", "Stopping removes stale angles from diagnostics")
                try await checkCameraLifecycle(require: require)
                try await checkPetReminder(directory: directory, require: require)
                try await checkHistoryUI(directory: directory, require: require)
                let data = try JSONSerialization.data(withJSONObject: ["passed": true, "checks": checks], options: [.prettyPrinted, .sortedKeys])
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("result.json"))
                print("Native smoke test passed: \(checks.count) checks")
                RunLoop.main.perform { NSApp.terminate(nil) }
            } catch {
                let data = try? JSONSerialization.data(withJSONObject: ["passed": false, "checks": checks, "error": error.localizedDescription], options: [.prettyPrinted])
                try? data?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("result.json"))
                fputs("Native smoke test failed: \(error)\n", stderr)
                manager.shutdown()
                exit(1)
            }
        }
    }

    @MainActor
    private func checkHistoryUI(directory: String, require: (Bool, String) throws -> Void) async throws {
        _ = try await webView.evaluateJavaScript("""
        (() => {
          const input = document.querySelector('#task-input');
          Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, '验证历史任务');
          input.dispatchEvent(new Event('input', { bubbles: true }));
        })()
        """)
        try await Task.sleep(nanoseconds: 100_000_000)
        _ = try await webView.evaluateJavaScript("document.querySelector('.task-form').requestSubmit()")
        try await Task.sleep(nanoseconds: 100_000_000)
        _ = try await webView.evaluateJavaScript("document.querySelector('.start-button').click()")
        try await Task.sleep(nanoseconds: 150_000_000)
        let id = try await webView.evaluateJavaScript("JSON.parse(localStorage.getItem('focus-on.v1')).session.id") as? String
        try require(id != nil && manager.schedule?.sessionId == id,
                    "WKWebView synchronizes the history session identity to the native schedule")
        if let id {
            let at = Date().timeIntervalSince1970 * 1000
            manager.onDistraction?("smoke-history-reminder", id, at)
            manager.onDistraction?("smoke-history-reminder", id, at)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        _ = try await webView.evaluateJavaScript("document.querySelector('.complete-task').click()")
        try await Task.sleep(nanoseconds: 100_000_000)
        let saved = try await webView.evaluateJavaScript("""
        (() => {
          const state = JSON.parse(localStorage.getItem('focus-on.v1'));
          const task = state.history[0];
          return state.session === null && task.title === '验证历史任务' && task.distractions === 1 &&
            task.completedAt > 0 && task.focusSeconds > 0;
        })()
        """) as? Bool
        try require(saved == true, "Native reminder bridge deduplicates and persists completed task metrics in WebKit")
        _ = try await webView.evaluateJavaScript("document.querySelector('.history-toggle').click()")
        try await Task.sleep(nanoseconds: 700_000_000)
        let visible = try await webView.evaluateJavaScript("""
        document.querySelector('.history-title').textContent === '验证历史任务' &&
        getComputedStyle(document.querySelector('.workspace')).visibility === 'hidden' &&
        document.querySelector('.history-page input') === null
        """) as? Bool
        try require(visible == true, "Native history page replaces the workspace without a composer")
        let image = try await webView.takeSnapshot(configuration: nil)
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("task-history.png"))
        }
    }
}
