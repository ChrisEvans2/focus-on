import AppKit
import FocusCore
import FocusVision

extension DebugApp {
    func smoke(directory: String) throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "GazeDebug", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let mapping = FrameMapping(image: CGSize(width: 1280, height: 720), bounds: bounds,
                                   crop: CGRect(x: 0, y: 0, width: 1, height: 1))
        try require(mapping.point(CGPoint(x: 0, y: 0)) == CGPoint(x: 0, y: 75), "Aspect-fit letterboxing must offset overlay points")
        try require(mapping.point(CGPoint(x: 1, y: 1)) == CGPoint(x: 800, y: 525), "Vision y must stay bottom-up")
        let cropped = FrameMapping(image: CGSize(width: 1000, height: 1000), bounds: bounds,
                                   crop: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        try require(cropped.point(CGPoint(x: 0.5, y: 0.5)) == CGPoint(x: 400, y: 300), "Zoom must transform pixels and landmarks together")
        try require(camera == nil, "Viewer must not start capture at launch")
        let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.darkGray.cgColor); context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        var overlay = VisionOverlay(); overlay.faces = [CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7)]
        func outline(_ x: Double) -> [CGPoint] {
            [CGPoint(x: x - 0.08, y: 0.55), CGPoint(x: x - 0.04, y: 0.59), CGPoint(x: x + 0.04, y: 0.59),
             CGPoint(x: x + 0.08, y: 0.55), CGPoint(x: x + 0.04, y: 0.51), CGPoint(x: x - 0.04, y: 0.51)]
        }
        overlay.leftEye = outline(0.35); overlay.rightEye = outline(0.65)
        overlay.leftPupil = [CGPoint(x: 0.35, y: 0.55)]; overlay.rightPupil = [CGPoint(x: 0.65, y: 0.55)]
        for points in [overlay.leftEye, overlay.rightEye] {
            context.beginPath(); context.move(to: CGPoint(x: points[0].x * 640, y: points[0].y * 480))
            for point in points.dropFirst() { context.addLine(to: CGPoint(x: point.x * 640, y: point.y * 480)) }
            context.closePath(); context.setFillColor(NSColor.white.cgColor); context.fillPath()
        }
        for p in overlay.leftPupil + overlay.rightPupil {
            context.setFillColor(NSColor.black.cgColor); context.fillEllipse(in: CGRect(x: p.x * 640 - 6, y: p.y * 480 - 6, width: 12, height: 12))
        }
        let left = EyeGeometry.measure(contour: overlay.leftEye.map { EyePoint(x: $0.x * 640, y: $0.y * 480) }, pupil: EyePoint(x: 224, y: 264))!
        let sample = FaceState(faceDetected: true, pitch: 13.7, yaw: 7.9, roll: 0, eyes: EyePair(left: left, right: left), faceCount: 1, confidence: 0.95)
        for i in 0...65 { engine.update(sample, at: Double(i) / 10) }
        preview.frameImage = context.makeImage(); preview.overlay = overlay; preview.sample = sample
        details.stringValue = diagnosticText(for: sample)
        try require(engine.config.gaze.eyelidAssistanceEnabled && engine.gaze.eyelids.reference != nil, "Debug viewer must calibrate the experimental eyelid cue")
        status.stringValue = "合成图形验证 · 未开启摄像头"
        let directoryURL = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        for zoom in [false, true] {
            preview.zoom = zoom; preview.needsDisplay = true
            let content = window.contentView!; content.layoutSubtreeIfNeeded()
            let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
            content.cacheDisplay(in: content.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: directoryURL.appendingPathComponent(zoom ? "zoom.png" : "full.png"))
        }
        stop()
        try require(preview.frameImage == nil && preview.overlay.leftEye.isEmpty, "Stopping must clear the camera image and raw landmarks")
        try require(!engine.gaze.calibrated, "Stopping must clear the gaze baseline")
        try require(engine.gaze.eyelids.reference == nil, "Stopping must clear the eyelid baseline")
        print("Gaze viewer checks passed: mapping, zoom, no auto-capture, synthetic rendering, stop cleanup")
    }
}
