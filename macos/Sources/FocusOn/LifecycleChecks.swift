import FocusVision
import Foundation
import AVFoundation
import FocusCore

/// Test-only capture source. Never selected by the normal application entry point.
private final class ControlledCamera: CameraCapturing {
    var starts = 0
    var stops = 0
    var samples: [(FaceState, Double) -> Void] = []
    var failures: [(String) -> Void] = []
    func start(onSample: @escaping (FaceState, Double) -> Void, onFailure: @escaping (String) -> Void) {
        starts += 1; samples.append(onSample); failures.append(onFailure)
    }
    func stop() { stops += 1 }
    func stop(completion: @escaping () -> Void) { stop(); completion() }
}

@MainActor
func checkCameraLifecycle(require: (Bool, String) throws -> Void) async throws {
    let plan = [FocusPhase(kind: "focus", seconds: 600)]
    let active = FocusSchedule(running: true, startedAt: 0, elapsed: 0, phases: plan, monitoring: true)
    let paused = FocusSchedule(running: false, startedAt: nil, elapsed: 0, phases: plan, monitoring: true)
    let settle = { try await Task.sleep(nanoseconds: 20_000_000) }

    let pendingCamera = ControlledCamera()
    var answerPermission: ((Bool) -> Void)?
    let pending = FocusSessionManager(camera: pendingCamera, authorization: { .notDetermined },
                                     requestAccess: { answerPermission = $0 }, epochTime: { 0 }, uptime: { 0 }, automaticTicks: false)
    pending.synchronize(active)
    try require(pending.status == "permission" && pendingCamera.starts == 0, "Camera waits for system permission")
    pending.synchronize(paused)
    answerPermission?(true)
    try await settle()
    try require(pendingCamera.starts == 0 && pending.status == "idle", "Permission granted after pause cannot start capture")
    pending.shutdown()

    let deniedCamera = ControlledCamera()
    let denied = FocusSessionManager(camera: deniedCamera, authorization: { .denied }, epochTime: { 0 }, uptime: { 0 }, automaticTicks: false)
    denied.synchronize(active); denied.tick()
    try require(denied.status == "denied" && denied.schedule?.running == true && deniedCamera.starts == 0,
                "Denied permission preserves timer and never retries automatically")
    denied.shutdown()

    let camera = ControlledCamera()
    var time = 0.0
    let manager = FocusSessionManager(camera: camera, authorization: { .authorized }, epochTime: { time }, uptime: { time }, automaticTicks: false)
    manager.synchronize(active)
    let oldSample = camera.samples[0], oldFailure = camera.failures[0]
    manager.stop()
    manager.synchronize(active)
    try require(camera.starts == 1 && manager.schedule == nil, "Native pause rejects an in-flight running web snapshot")
    manager.synchronize(paused)
    oldSample(FaceState(faceDetected: true, pitch: 0, yaw: 0), 1)
    oldFailure("stale failure")
    try await settle()
    try require(manager.status == "idle" && !manager.reminder.visible && camera.stops > 0,
                "Queued samples and failures cannot revive a paused session")
    manager.synchronize(active)
    oldFailure("old session failure")
    try await settle()
    try require(manager.status == "calibrating" && camera.starts == 2,
                "A previous capture generation cannot fail a resumed session")
    time = 9; manager.tick()
    try require(manager.status == "unavailable" && !manager.reminder.visible,
                "Eight seconds without frames stops capture and exposes retry")
    manager.retry()
    try require(camera.starts == 3 && manager.status == "calibrating", "Explicit retry starts a fresh capture session")
    let late = camera.samples.last!
    manager.shutdown()
    manager.synchronize(active); manager.retry(); manager.recalibrate()
    late(FaceState(faceDetected: true, pitch: 0, yaw: 0), 10)
    try await settle()
    try require(camera.starts == 3 && manager.status == "idle" && manager.schedule == nil,
                "Shutdown rejects late web messages, retry and camera callbacks")

    let phaseCamera = ControlledCamera()
    time = 0
    let phases = FocusSessionManager(camera: phaseCamera, authorization: { .authorized }, epochTime: { time }, uptime: { time }, automaticTicks: false)
    phases.synchronize(FocusSchedule(running: true, startedAt: 0, elapsed: 0,
        phases: [FocusPhase(kind: "focus", seconds: 2), FocusPhase(kind: "break", seconds: 2), FocusPhase(kind: "focus", seconds: 2)], monitoring: true))
    time = 2; phases.tick()
    try require(phases.status == "idle" && phaseCamera.stops > 0, "Native deadline closes capture at a break without web ticks")
    time = 4; phases.tick()
    try require(phaseCamera.starts == 2 && phases.status == "calibrating", "Next focus phase starts with a fresh calibration")
    time = 6; phases.tick()
    try require(phases.status == "idle" && phaseCamera.stops == 2, "Native deadline closes capture at session completion")
    phases.shutdown()

    let countCamera = ControlledCamera()
    time = 0
    let counting = FocusSessionManager(camera: countCamera, authorization: { .authorized },
        epochTime: { time }, uptime: { time }, automaticTicks: false)
    var distractions: [(String, String, Double)] = []
    counting.onDistraction = { distractions.append(($0, $1, $2)) }
    counting.synchronize(FocusSchedule(running: true, startedAt: 0, elapsed: 0, phases: plan,
                                      monitoring: true, sessionId: "history-session"))
    for i in 0...70 {
        time = Double(i) / 10
        counting.consume(FaceState(faceDetected: true, pitch: 0, yaw: 0), at: time)
    }
    for i in 71...190 {
        time = Double(i) / 10
        counting.consume(FaceState(faceDetected: true, pitch: 0, yaw: 55), at: time)
    }
    try require(distractions.count == 1 && distractions.first?.1 == "history-session" &&
                (distractions.first?.2 ?? 0) > 7000,
                "A sustained distraction emits one timestamped history event for its session")
    for i in 191...195 {
        time = Double(i) / 10
        counting.consume(FaceState(faceDetected: true, pitch: 0, yaw: 0), at: time)
    }
    for i in 196...210 {
        time = Double(i) / 10
        counting.consume(FaceState(faceDetected: true, pitch: 0, yaw: 55), at: time)
    }
    try require(distractions.count == 1, "An incomplete return cannot count the same reminder twice")
    for i in 211...550 {
        time = Double(i) / 10
        counting.consume(FaceState(faceDetected: true, pitch: 0, yaw: 0), at: time)
    }
    for i in 551...680 {
        time = Double(i) / 10
        counting.consume(FaceState(faceDetected: true, pitch: 0, yaw: 55), at: time)
    }
    try require(distractions.count == 2 && distractions[0].0 != distractions[1].0,
                "A later reminder after recovery and cooldown has its own unique history event")
    counting.shutdown()
}
