import AppKit
import AVFoundation
import CoreImage
import FocusCore
import FocusVision

final class DebugApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let preview = PreviewView()
    let details = NSTextField(wrappingLabelWithString: "摄像头未开启。先暂停 Focus On，再点击开始。")
    let status = NSTextField(labelWithString: "仅调试 · 不触发宠物提醒 · 不保存或上传画面")
    var toggleButton: NSButton!
    var camera: CameraMonitor?
    var engine: AttentionEngine = {
        var config = AttentionConfig(); config.gaze.eyelidAssistanceEnabled = true
        return AttentionEngine(config: config)
    }()
    private let context = CIContext()
    private let pendingFrame = DispatchSemaphore(value: 1)
    private var generation = 0
    private var running = false
    private var lastFrame = 0.0
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(), appMenuItem = NSMenuItem(); menu.addItem(appMenuItem)
        appMenuItem.submenu = NSMenu()
        appMenuItem.submenu?.addItem(withTitle: "退出视线调试", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1140, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Focus On · 实时视线调试"; window.delegate = self
        window.minSize = NSSize(width: 1000, height: 700); window.isReleasedWhenClosed = false
        let root = NSView(); window.contentView = root
        toggleButton = NSButton(title: "开始摄像头", target: self, action: #selector(toggle))
        toggleButton.bezelStyle = .rounded
        let reset = NSButton(title: "重新建立基准", target: self, action: #selector(resetReference)); reset.bezelStyle = .rounded
        let zoom = NSButton(checkboxWithTitle: "放大眼部", target: self, action: #selector(setZoom(_:)))
        let marks = NSButton(checkboxWithTitle: "显示标记", target: self, action: #selector(setMarks(_:))); marks.state = .on
        let eyelids = NSButton(checkboxWithTitle: "眼睑辅助（实验）", target: self, action: #selector(setEyelids(_:))); eyelids.state = .on
        let controls = NSStackView(views: [toggleButton, reset, zoom, marks, eyelids]); controls.spacing = 16
        details.font = .monospacedSystemFont(ofSize: 12, weight: .regular); details.isSelectable = true
        status.font = .systemFont(ofSize: 13)
        let legend = NSTextField(wrappingLabelWithString: "绿：左眼轮廓 · 蓝：右眼轮廓 · 红十字：瞳孔 · 橙：点位存在但几何校验未通过\n未镜像画面；眼睛轮廓是眼睑关键点，不是眼眶骨或虹膜边缘。画面与标记来自同一帧。")
        legend.font = .systemFont(ofSize: 13)
        for view in [controls, preview, details, status, legend] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: root.topAnchor, constant: 16), controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            status.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 12), status.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            preview.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 12), preview.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
            preview.bottomAnchor.constraint(equalTo: legend.topAnchor, constant: -12),
            details.leadingAnchor.constraint(equalTo: preview.trailingAnchor, constant: 16), details.topAnchor.constraint(equalTo: preview.topAnchor),
            details.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16), details.widthAnchor.constraint(equalToConstant: 355),
            details.bottomAnchor.constraint(lessThanOrEqualTo: legend.topAnchor, constant: -12),
            legend.leadingAnchor.constraint(equalTo: controls.leadingAnchor), legend.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            legend.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.stop() })
        }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if let index = CommandLine.arguments.firstIndex(of: "--smoke-test"), CommandLine.arguments.count > index + 1 {
            do { try smoke(directory: CommandLine.arguments[index + 1]); NSApp.terminate(nil) }
            catch { fputs("Debug viewer check failed: \(error)\n", stderr); exit(1) }
        }
    }
    @objc func setZoom(_ sender: NSButton) { preview.zoom = sender.state == .on; preview.needsDisplay = true }
    @objc func setMarks(_ sender: NSButton) { preview.marks = sender.state == .on; preview.needsDisplay = true }
    @objc func setEyelids(_ sender: NSButton) {
        var config = engine.config; config.gaze.eyelidAssistanceEnabled = sender.state == .on
        engine = AttentionEngine(config: config)
        details.stringValue = "已切换眼睑辅助；正常看屏幕约 6 秒，重新建立基准。"
    }
    func diagnosticText(for sample: FaceState) -> String {
        let base = engine.diagnosticText(for: sample)
        guard engine.config.gaze.eyelidAssistanceEnabled else { return base }
        func value(_ v: Double?) -> String { v.map { String(format: "%.3f", $0) } ?? "—" }
        return base + "\n\n" + engine.gaze.eyelids.diagnosticText
            + "\n当前高/宽  左 \(value(sample.eyes?.left?.openness))  右 \(value(sample.eyes?.right?.openness))"
            + "\n实验信号；眯眼、睁大眼也可能触发。"
    }
    @objc func resetReference() { engine.reset(); details.stringValue = "已清除基准；正常看工作屏幕，等待约 6 秒自动采样。" }
    @objc func toggle() {
        if running { stop(); return }
        running = true; generation += 1; let token = generation
        toggleButton.title = "停止摄像头"; engine.reset()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: startCapture(token: token)
        case .notDetermined:
            status.stringValue = "请允许调试工具使用摄像头；画面仅在本机显示。"
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.running, self.generation == token else { return }
                    if granted { self.startCapture(token: token) }
                    else { self.stop(); self.status.stringValue = "未获摄像头权限，请在系统设置中允许 Focus On Gaze Debug。" }
                }
            }
        default: stop(); status.stringValue = "未获摄像头权限，请在系统设置中允许 Focus On Gaze Debug。"
        }
    }
    private func startCapture(token: Int) {
        lastFrame = ProcessInfo.processInfo.systemUptime
        let context = self.context, pending = pendingFrame
        camera = CameraMonitor(includeEyes: true, onDebugFrame: { [weak self] buffer, overlay, sample, time in
            // Keep at most one displayed frame pending; never queue old camera images.
            guard pending.wait(timeout: .now()) == .success else { return }
            let image = CIImage(cvPixelBuffer: buffer)
            guard let rendered = context.createCGImage(image, from: image.extent) else { pending.signal(); return }
            DispatchQueue.main.async { [weak self] in
                defer { pending.signal() }
                guard let self, self.running, self.generation == token else { return }
                self.lastFrame = time; self.engine.update(sample, at: time)
                self.preview.frameImage = rendered; self.preview.overlay = overlay; self.preview.sample = sample; self.preview.needsDisplay = true
                self.details.stringValue = self.diagnosticText(for: sample)
                self.status.stringValue = "实时画面 \(rendered.width)×\(rendered.height) · 仅本地显示、不保存 · 眼睑辅助仅在本调试器启用"
            }
        })
        camera?.start(onSample: { _, _ in }, onFailure: { [weak self] message in
            DispatchQueue.main.async {
                guard let self, self.running, self.generation == token else { return }
                self.stop(); self.status.stringValue = message
            }
        })
        timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.running else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if now - self.lastFrame > 1.2 {
                self.preview.clear(); self.engine.update(.unavailable, at: now)
                self.details.stringValue = "暂无新画面；旧画面与点位已清除。"
            }
            if now - self.lastFrame > 8 { self.stop(); self.status.stringValue = "摄像头没有提供画面，请暂停其他摄像头工具后重试。" }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func stop(completion: @escaping () -> Void = {}) {
        running = false; generation += 1; timer?.invalidate(); timer = nil
        preview.clear(); engine.reset(); details.stringValue = "摄像头已停止，画面和基准已清除。"
        toggleButton?.title = "开始摄像头"; toggleButton?.isEnabled = false
        status.stringValue = "仅调试 · 不触发宠物提醒 · 不保存或上传画面"
        let oldCamera = camera; camera = nil
        let finish = { [weak self] in self?.toggleButton?.isEnabled = true; completion() }
        if let oldCamera { oldCamera.stop(completion: finish) } else { finish() }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        stop { DispatchQueue.main.async { sender.reply(toApplicationShouldTerminate: true) } }; return .terminateLater
    }
}

let app = NSApplication.shared
let delegate = DebugApp()
app.delegate = delegate
app.run()
