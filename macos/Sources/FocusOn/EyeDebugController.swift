import FocusVision
import AppKit
import AVFoundation
import FocusCore

private final class EyeDebugBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: bounds).fill()
    }
}

private final class EyeDiagram: NSView {
    var eyes: EyePair? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        for (index, eye) in [eyes?.left, eyes?.right].enumerated() {
            let rect = NSRect(x: CGFloat(index) * bounds.width / 2 + 30, y: 25, width: bounds.width / 2 - 60, height: 75)
            let label = index == 0 ? "左眼" : "右眼"
            (label as NSString).draw(at: NSPoint(x: rect.midX - 16, y: 113), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])
            guard let eye else {
                ("点位不可用 / 眨眼" as NSString).draw(at: NSPoint(x: rect.midX - 54, y: 54), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor])
                continue
            }
            func point(_ p: EyePoint) -> NSPoint { NSPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height) }
            let outline = NSBezierPath()
            for (i, p) in eye.contour.enumerated() { if i == 0 { outline.move(to: point(p)) } else { outline.line(to: point(p)) } }
            outline.close(); outline.lineWidth = 2
            NSColor(calibratedRed: 0.35, green: 0.49, blue: 0.43, alpha: 1).setStroke(); outline.stroke()
            let p = point(eye.pupil)
            NSColor(calibratedRed: 0.35, green: 0.49, blue: 0.43, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)).fill()
        }
    }
}

/// An opt-in, memory-only experiment. Gaze results never enter the reminder state machine.
final class EyeDebugController: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow!
    private let camera = CameraMonitor(includeEyes: true)
    private let estimator = GazeEstimator()
    var prepareToStart: (@escaping () -> Void) -> Void = { $0() }
    private let diagram = EyeDiagram()
    private let status = NSTextField(wrappingLabelWithString: "点击开始测试。摄像头画面不显示、不保存，测试结果仅保留在这个窗口。")
    private let angles = NSTextField(labelWithString: "Pitch —    Yaw —    Roll —")
    private let pupils = NSTextField(labelWithString: "左瞳孔 —                  右瞳孔 —")
    private let direction = NSTextField(labelWithString: "先采样「屏幕中央」，建立视线基线")
    private let progress = NSTextField(labelWithString: "依次选择目标采样：中央 → 顶部 → 底部 → 键盘 → 左边 → 右边")
    private let comparison = NSTextField(wrappingLabelWithString: "采样中央和键盘后，这里会比较两者的差异与测量波动。")
    private let results = NSTextField(labelWithString: "")
    private var startButton: NSButton!
    private var sampleButtons: [NSButton] = []
    private var timer: Timer?
    private var running = false
    var isRunning: Bool { running }
    private var authorizedCapture = false
    private var generation = 0
    private var lastFrame = 0.0
    private var latest: FaceState?
    private var captureTarget: Int?
    private var captureStart = 0.0
    private var captureEnd = 0.0
    private var collected: [(EyePoint, Double?, Double?)] = []
    private var references: [Int: GazeReference] = [:]
    private var angleReferences: [Int: (Double?, Double?)] = [:]
    private let targets = ["屏幕中央", "屏幕顶部", "屏幕底部", "键盘", "左边", "右边"]

    func show() {
        if window == nil { buildWindow() }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 790, height: 750), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.title = "Focus On · 眼动测试"; window.delegate = self; window.isReleasedWhenClosed = false; window.center()
        let root = EyeDebugBackground(); window.contentView = root
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -26), stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24)])
        let heading = NSTextField(labelWithString: "看看眼睛能告诉我们什么")
        heading.font = .systemFont(ofSize: 23, weight: .semibold)
        stack.addArrangedSubview(heading)
        let subtitle = NSTextField(wrappingLabelWithString: "实验功能 · 只观察信号，不触发宠物提醒。采样期间请保持头部自然稳定，按提示移动视线。")
        subtitle.font = .systemFont(ofSize: 13); subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitle)
        startButton = NSButton(title: "开始测试", target: self, action: #selector(toggle))
        startButton.bezelStyle = .rounded
        let clear = NSButton(title: "清空采样", target: self, action: #selector(clearReferences)); clear.bezelStyle = .rounded
        let buttons = NSStackView(views: [startButton, clear]); buttons.spacing = 10
        stack.addArrangedSubview(buttons)
        status.font = .systemFont(ofSize: 13); stack.addArrangedSubview(status)
        diagram.translatesAutoresizingMaskIntoConstraints = false
        diagram.heightAnchor.constraint(equalToConstant: 142).isActive = true
        stack.addArrangedSubview(diagram)
        for label in [angles, pupils] { label.font = .monospacedSystemFont(ofSize: 13, weight: .regular); stack.addArrangedSubview(label) }
        direction.font = .systemFont(ofSize: 19, weight: .medium); stack.addArrangedSubview(direction)
        progress.font = .systemFont(ofSize: 12); stack.addArrangedSubview(progress)
        sampleButtons = targets.enumerated().map { index, title in
            let button = NSButton(title: title, target: self, action: #selector(sample(_:)))
            button.bezelStyle = .rounded; button.tag = index; button.isEnabled = false; return button
        }
        let targetRow = NSStackView(views: sampleButtons); targetRow.spacing = 6
        stack.addArrangedSubview(targetRow)
        results.font = .monospacedSystemFont(ofSize: 12, weight: .regular); results.maximumNumberOfLines = 8
        stack.addArrangedSubview(results)
        comparison.font = .systemFont(ofSize: 12); comparison.textColor = .secondaryLabelColor
        stack.addArrangedSubview(comparison)
        let note = NSTextField(wrappingLabelWithString: "x 向图像右侧增大，y 向下增大；方向按你本人的左右描述。几何示意并非摄像头画面。更换坐姿后请清空并重新采样。")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor; stack.addArrangedSubview(note)
        for view in [subtitle, status, diagram, angles, pupils, progress, results, comparison, note] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        renderReferences()
    }
    @objc private func toggle() { if running { stop() } else { start() } }
    private func start() {
        running = true; authorizedCapture = false; generation += 1
        let token = generation
        clearReferences(); startButton.title = "停止测试"
        status.stringValue = "正在准备摄像头；当前专注会暂停。"
        prepareToStart { [weak self] in
            guard let self, self.running, self.generation == token else { return }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: self.beginCapture(token: token)
            case .notDetermined:
                self.status.stringValue = "请允许摄像头权限，所有分析都在本机完成。"
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self, self.running, self.generation == token else { return }
                        if granted { self.beginCapture(token: token) }
                        else { self.stop(); self.status.stringValue = "摄像头权限未获允许，请在系统设置中允许 Focus On 使用摄像头。" }
                    }
                }
            default:
                self.stop(); self.status.stringValue = "摄像头权限未获允许，请在系统设置中允许 Focus On 使用摄像头。"
            }
        }
    }
    private func beginCapture(token: Int) {
        authorizedCapture = true; lastFrame = ProcessInfo.processInfo.systemUptime
        sampleButtons.forEach { $0.isEnabled = true }
        status.stringValue = "正在读取眼部点位，先采样「屏幕中央」。"
        timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        camera.start(onSample: { [weak self] sample, time in
            DispatchQueue.main.async {
                guard let self, self.running, self.generation == token else { return }
                self.lastFrame = time; self.latest = sample
                self.render(sample, at: time)
                if self.captureTarget != nil, time >= self.captureStart, time <= self.captureEnd, let point = sample.eyes?.center {
                    self.collected.append((point, sample.pitch, sample.yaw))
                }
            }
        }, onFailure: { [weak self] message in
            DispatchQueue.main.async {
                guard let self, self.running, self.generation == token else { return }
                self.stop(); self.status.stringValue = message
            }
        })
    }
    func stop(completion: @escaping () -> Void = {}) {
        running = false; authorizedCapture = false; generation += 1
        timer?.invalidate(); timer = nil; captureTarget = nil; collected.removeAll(); latest = nil
        estimator.reset(); diagram.eyes = nil
        startButton?.title = "开始测试"; sampleButtons.forEach { $0.isEnabled = false }
        angles.stringValue = "Pitch —    Yaw —    Roll —"; pupils.stringValue = "左瞳孔 —                  右瞳孔 —"
        direction.stringValue = "测试已停止"; status.stringValue = "摄像头已关闭。采样结果保留到清空或关闭窗口。"
        camera.stop(completion: completion)
    }
    func windowWillClose(_ notification: Notification) { stop(); clearReferences() }
    @objc private func clearReferences() {
        captureTarget = nil; collected.removeAll(); references.removeAll(); angleReferences.removeAll(); estimator.reset()
        sampleButtons.forEach { $0.isEnabled = running && authorizedCapture }
        progress.stringValue = "依次选择目标采样：中央 → 顶部 → 底部 → 键盘 → 左边 → 右边"
        renderReferences()
    }
    @objc private func sample(_ button: NSButton) {
        guard running, authorizedCapture else { return }
        captureTarget = button.tag; collected.removeAll()
        captureStart = ProcessInfo.processInfo.systemUptime + 2
        captureEnd = captureStart + 2.5
        sampleButtons.forEach { $0.isEnabled = false }
        tick()
    }
    private func tick() {
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastFrame > 1 {
            diagram.eyes = nil; estimator.update(nil, at: now)
            angles.stringValue = "Pitch —    Yaw —    Roll —"; pupils.stringValue = "左瞳孔 —                  右瞳孔 —"
            direction.stringValue = "暂无新画面 · 无法判断"
        }
        if now - lastFrame > 8 { stop(); status.stringValue = "摄像头没有提供画面，请检查连接后重新开始测试。"; return }
        guard let target = captureTarget else { return }
        if now < captureStart { progress.stringValue = "请看「\(targets[target])」· \(Int(ceil(captureStart - now))) 秒后采样" }
        else if now < captureEnd { progress.stringValue = "保持看「\(targets[target])」· 正在采样 \(collected.count) 帧" }
        else {
            if let reference = GazeReference(samples: collected.map { $0.0 }), reference.stable {
                references[target] = reference
                func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
                angleReferences[target] = (average(collected.compactMap { $0.1 }), average(collected.compactMap { $0.2 }))
                if target == 0 { estimator.calibrate(reference) }
                progress.stringValue = "「\(targets[target])」已采样 \(reference.sampleCount) 帧。可以测试下一个方向。"
            } else { progress.stringValue = "有效样本不足或波动过大，请改善光线、保持头部稳定后重试「\(targets[target])」。" }
            captureTarget = nil; collected.removeAll(); sampleButtons.forEach { $0.isEnabled = true }; renderReferences()
        }
    }
    private func number(_ n: Double?, digits: Int = 2) -> String { n.map { String(format: "%.*f", digits, $0) } ?? "—" }
    func render(_ sample: FaceState, at time: Double) {
        diagram.eyes = sample.eyes
        angles.stringValue = "Pitch \(number(sample.pitch, digits: 1))°    Yaw \(number(sample.yaw, digits: 1))°    Roll \(number(sample.roll, digits: 1))°"
        pupils.stringValue = "左瞳孔 \(number(sample.eyes?.left?.pupil.x)), \(number(sample.eyes?.left?.pupil.y))    右瞳孔 \(number(sample.eyes?.right?.pupil.x)), \(number(sample.eyes?.right?.pupil.y))"
        let gaze = estimator.update(sample.eyes, at: time)
        let names: [ApproximateGaze: String] = [.unavailable: "无法判断 · 点位缺失、眨眼或双眼不一致", .uncalibrated: "先采样「屏幕中央」，建立视线基线", .center: "接近正视（估计）", .down: "↓ 向下看（估计）", .up: "↑ 向上看（估计）", .left: "← 向左看（估计）", .right: "→ 向右看（估计）"]
        direction.stringValue = names[gaze]!
        if !sample.valid { status.stringValue = "画面太暗、多人入镜或识别不可靠；暂不判断。" }
        else if !sample.faceDetected { status.stringValue = "未检测到人脸，请回到摄像头范围内。" }
        else if sample.eyes?.center == nil { status.stringValue = "眼部点位暂不可用。请保持单人入镜、面部有光，避免眼镜反光。" }
        else { status.stringValue = "双眼点位可用 · Δx \(number(estimator.delta?.x)) / Δy \(number(estimator.delta?.y)) · 仅测试，不触发提醒" }
    }
    private func renderReferences() {
        results.stringValue = targets.enumerated().map { index, name in
            guard let r = references[index] else { return "\(name)  —" }
            return "\(name)  x \(number(r.point.x))  y \(number(r.point.y))  波动 ±\(number(r.noise.y))  pitch \(number(angleReferences[index]?.0, digits: 1))°  yaw \(number(angleReferences[index]?.1, digits: 1))°"
        }.joined(separator: "\n")
        guard let center = references[0], let keyboard = references[3] else {
            comparison.stringValue = "采样中央和键盘后，这里会比较两者的差异与测量波动。"; return
        }
        let delta = keyboard.point.y - center.point.y
        let distinct = keyboard.separatesVertically(from: center)
        comparison.stringValue = "键盘相对中央 Δy \(number(delta))。" + (distinct ? "本次垂直信号有可分差异；仍需重复采样验证。" : "本次差异不足以稳定区分，不建议直接接入提醒。") + (delta < -0.08 ? " 当前方向与预期相反，请重新采样核对。" : "")
    }
}
