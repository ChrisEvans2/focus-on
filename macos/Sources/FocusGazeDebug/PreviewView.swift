import AppKit
import FocusVision
import FocusCore

struct FrameMapping {
    let crop: CGRect // Normalized image coordinates, bottom-left origin.
    let display: CGRect
    init(image: CGSize, bounds: CGRect, crop: CGRect) {
        self.crop = crop
        let width = image.width * crop.width, height = image.height * crop.height
        let scale = min(bounds.width / width, bounds.height / height)
        display = CGRect(x: bounds.midX - width * scale / 2, y: bounds.midY - height * scale / 2,
                         width: width * scale, height: height * scale)
    }
    func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: display.minX + (p.x - crop.minX) / crop.width * display.width,
                y: display.minY + (p.y - crop.minY) / crop.height * display.height)
    }
}

final class PreviewView: NSView {
    var frameImage: CGImage?
    var overlay = VisionOverlay()
    var sample: FaceState?
    var zoom = false
    var marks = true
    func clear() { frameImage = nil; sample = nil; overlay = VisionOverlay(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        guard let frameImage else {
            ("点击「开始摄像头」查看实时画面" as NSString).draw(at: NSPoint(x: 24, y: bounds.midY),
                withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.white])
            return
        }
        let size = CGSize(width: frameImage.width, height: frameImage.height)
        var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
        let eyes = overlay.leftEye + overlay.rightEye
        if zoom, let first = eyes.first {
            let eyeBox = eyes.reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
            if eyeBox.width > 0.01 {
                crop = eyeBox.insetBy(dx: -eyeBox.width * 0.25, dy: -max(0.035, eyeBox.height))
                    .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            }
        }
        let mapping = FrameMapping(image: size, bounds: bounds, crop: crop)
        let image = NSImage(cgImage: frameImage, size: size)
        image.draw(in: mapping.display,
                   from: CGRect(x: crop.minX * size.width, y: crop.minY * size.height,
                                width: crop.width * size.width, height: crop.height * size.height),
                   operation: .copy, fraction: 1)
        guard marks else { return }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: mapping.display).addClip()
        for face in overlay.faces {
            let a = mapping.point(face.origin), b = mapping.point(CGPoint(x: face.maxX, y: face.maxY))
            let path = NSBezierPath(rect: CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
            NSColor.systemYellow.setStroke(); path.lineWidth = 1; path.stroke()
        }
        func drawEye(_ outline: [CGPoint], _ pupils: [CGPoint], _ color: NSColor, _ label: String, _ accepted: Bool) {
            let stroke = accepted ? color : NSColor.systemOrange
            let path = NSBezierPath()
            for (index, p) in outline.enumerated() {
                let point = mapping.point(p)
                if index == 0 { path.move(to: point) } else { path.line(to: point) }
                stroke.setFill(); NSBezierPath(ovalIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)).fill()
            }
            path.close(); stroke.setStroke(); path.lineWidth = 1.5; path.stroke()
            if let first = outline.first {
                let p = mapping.point(first)
                (label + (accepted ? "" : " · 未采信") as NSString).draw(at: CGPoint(x: p.x, y: p.y + 14),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: stroke,
                                     .backgroundColor: NSColor.black.withAlphaComponent(0.7)])
            }
            for pupil in pupils {
                let p = mapping.point(pupil), cross = NSBezierPath()
                cross.move(to: CGPoint(x: p.x - 6, y: p.y)); cross.line(to: CGPoint(x: p.x + 6, y: p.y))
                cross.move(to: CGPoint(x: p.x, y: p.y - 6)); cross.line(to: CGPoint(x: p.x, y: p.y + 6))
                NSColor.systemRed.setStroke(); cross.lineWidth = 2; cross.stroke()
            }
        }
        drawEye(overlay.leftEye, overlay.leftPupil, .systemGreen, "左眼", sample?.eyes?.left != nil)
        drawEye(overlay.rightEye, overlay.rightPupil, .systemCyan, "右眼", sample?.eyes?.right != nil)
    }
}
