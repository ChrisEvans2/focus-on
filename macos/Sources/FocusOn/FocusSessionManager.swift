import FocusVision
import Foundation
import AVFoundation
import FocusCore

final class FocusSessionManager {
    let camera: CameraCapturing
    let engine = AttentionEngine()
    let reminder = ReminderController()
    var onStatus: ((String, String) -> Void)?
    var onDiagnostics: ((String) -> Void)?
    var onDistraction: ((_ id: String, _ sessionId: String, _ at: Double) -> Void)?
    private(set) var diagnosticText = "尚未开始专注监测。"
    private(set) var schedule: FocusSchedule?
    private(set) var status = "idle"
    private var timer: Timer?
    private var monitoring = false
    private var failed = false
    private var terminated = false
    private var awaitingPauseAcknowledgement = false
    private let authorization: () -> AVAuthorizationStatus
    private let requestAccess: (@escaping (Bool) -> Void) -> Void
    private let epochTime: () -> Double
    private let uptime: () -> Double
    private var generation = 0
    private var lastSample = 0.0
    private var startedMonitoring = 0.0
    private var lastMessage = ""

    init(camera: CameraCapturing = CameraMonitor(includeEyes: true),
         authorization: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .video) },
         requestAccess: @escaping (@escaping (Bool) -> Void) -> Void = { AVCaptureDevice.requestAccess(for: .video, completionHandler: $0) },
         epochTime: @escaping () -> Double = { Date().timeIntervalSince1970 },
         uptime: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         automaticTicks: Bool = true) {
        self.camera = camera; self.authorization = authorization; self.requestAccess = requestAccess
        self.epochTime = epochTime; self.uptime = uptime
        if automaticTicks {
            timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer!, forMode: .common)
        }
    }

    func synchronize(_ schedule: FocusSchedule) {
        guard !terminated else { return }
        guard schedule.isValid else { stop(); return }
        // A native pause (close/sleep/menu) wins over in-flight running web snapshots.
        if awaitingPauseAcknowledgement {
            guard !schedule.running else { return }
            awaitingPauseAcknowledgement = false
        }
        if self.schedule?.sessionId != schedule.sessionId { stopMonitoring() }
        self.schedule = schedule
        if !schedule.running || !schedule.monitoring { failed = false }
        tick()
    }
    func retry() { guard !terminated else { return }; failed = false; stopMonitoring(); tick() }
    func recalibrate() {
        guard !terminated else { return }
        guard monitoring else { retry(); return }
        engine.reset(); reminder.hide(immediate: true)
        startedMonitoring = uptime()
        publish("calibrating", "正在重新适应坐姿，继续正常使用即可")
    }
    func stop() {
        awaitingPauseAcknowledgement = awaitingPauseAcknowledgement || schedule?.running == true
        schedule = nil; failed = false; stopMonitoring()
        publish("idle", "摄像头已关闭")
    }
    func shutdown(completion: @escaping () -> Void = {}) {
        terminated = true; stop(); timer?.invalidate(); camera.stop(completion: completion)
    }

    func tick() {
        guard !terminated else { return }
        let now = epochTime()
        guard let schedule, schedule.shouldMonitor(at: now) else {
            stopMonitoring()
            if schedule?.phase(at: now) == "break" { publish("idle", "休息中 · 摄像头已关闭") }
            else { publish("idle", "摄像头已关闭") }
            return
        }
        if !monitoring && !failed { startMonitoring() }
        guard monitoring, status != "permission" else { return }
        let uptime = uptime()
        if uptime - lastSample > 1.2 {
            engine.update(.unavailable, at: uptime)
            reminder.hide(immediate: true)
            updateDiagnostics("暂无新画面，连续判断已重置；计时继续。")
            publish("unknown", "等待摄像头画面，计时继续")
        }
        if uptime - lastSample > 8 {
            fail("摄像头未提供画面，请检查连接后重试")
        }
    }

    private func startMonitoring() {
        monitoring = true; generation += 1
        let token = generation
        engine.reset(); startedMonitoring = uptime(); lastSample = startedMonitoring
        switch authorization() {
        case .authorized: beginCapture(token: token)
        case .notDetermined:
            publish("permission", "请允许使用摄像头；画面只在本机处理")
            requestAccess { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.monitoring, self.generation == token else { return }
                    if granted { self.beginCapture(token: token) }
                    else { self.fail("未获摄像头权限，仍可继续计时", code: "denied") }
                }
            }
        default: fail("未获摄像头权限，仍可继续计时", code: "denied")
        }
    }

    private func beginCapture(token: Int) {
        guard schedule?.shouldMonitor(at: epochTime()) == true else { stopMonitoring(); return }
        lastSample = uptime()
        publish("calibrating", "正在自动适应坐姿，计时正常进行")
        camera.start(onSample: { [weak self] sample, time in
            DispatchQueue.main.async {
                guard let self, self.monitoring, self.generation == token else { return }
                // A queued result cannot re-show the pet after the phase has ended.
                guard self.schedule?.shouldMonitor(at: self.epochTime()) == true else { self.tick(); return }
                self.lastSample = time
                self.consume(sample, at: time)
            }
        }, onFailure: { [weak self] message in
            DispatchQueue.main.async {
                guard let self, self.monitoring, self.generation == token else { return }
                self.fail(message)
            }
        })
    }

    /// Also used by the native integration smoke test; production samples only come from Vision.
    func consume(_ sample: FaceState, at time: Double) {
        let wasAlerting = engine.alertVisible
        let state = engine.update(sample, at: time)
        if engine.alertVisible && !reminder.visible { reminder.show() }
        else if !engine.alertVisible && reminder.visible { reminder.hide(immediate: state == .unknown) }
        // Count a new reminder episode, never individual frames or returning-state jitter.
        if engine.alertVisible && !wasAlerting, let schedule, let sessionId = schedule.sessionId,
           schedule.shouldMonitor(at: epochTime()) {
            onDistraction?(UUID().uuidString, sessionId, epochTime() * 1000)
        }
        let message: String
        switch state {
        case .calibrating:
            message = time - startedMonitoring > 15 ? "仍在等待稳定画面，计时正常进行；可检查光线和摄像头位置" : "正在自动适应坐姿，计时正常进行"
        case .focused: message = engine.gaze.calibrated && engine.gaze.direction != .unavailable ? "头部与视线监测中" : "头部监测中 · 眼部信号不足"
        case .suspected: message = sample.faceDetected ? "正在确认持续偏离" : "暂未看到你，正在确认"
        case .distracted: message = "看回工作屏幕，宠物会自动离开"
        case .away: message = "暂时没看到你，回来后提醒会自动消失"
        case .returning: message = "欢迎回来"
        case .unknown: message = sample.issue?.rawValue ?? "信号暂不可靠，已暂停提醒"
        }
        publish(state.rawValue, message)
        updateDiagnostics(engine.diagnosticText(for: sample))
    }

    private func fail(_ message: String, code: String = "unavailable") {
        stopMonitoring(); failed = true; publish(code, message)
    }
    private func stopMonitoring() {
        if monitoring { monitoring = false; generation += 1; camera.stop(); engine.reset() }
        if reminder.visible || !reminder.panels.isEmpty { reminder.hide(immediate: true) }
    }
    private func publish(_ code: String, _ message: String) {
        if ["idle", "permission", "denied", "unavailable", "calibrating"].contains(code) {
            if code != "calibrating" || engine.baselinePitch == nil { updateDiagnostics(message) }
        }
        guard status != code || lastMessage != message else { return }
        status = code; lastMessage = message; onStatus?(code, message)
    }
    private func updateDiagnostics(_ text: String) {
        diagnosticText = text; onDiagnostics?(text)
    }
}
