import Foundation

public struct AttentionConfig {
    public var yawThreshold = 30.0
    public var pitchThreshold = 18.0
    public var returnYawThreshold = 22.0
    public var returnPitchThreshold = 12.0
    public var suspectedDuration = 2.0
    public var distractionDuration = 7.0
    public var missingSuspectedDuration = 3.0
    public var awayDuration = 9.0
    public var returnDuration = 1.5
    public var reminderCooldown = 25.0
    public var calibrationDuration = 1.5
    public var startupObservationDuration = 6.0
    public var calibrationMinimumSamples = 8
    public var calibrationTolerance = 8.0
    public var adaptationStableDuration = 10.0
    public var adaptationTolerance = 3.0
    public var adaptationPitchWindow = 6.0
    public var adaptationYawWindow = 8.0
    public var adaptationMaximumDrift = 4.0
    public var adaptationTimeConstant = 20.0
    public var smoothingAlpha = 0.3
    public var maximumSampleGap = 1.0
    public var gaze = AttentionGazeConfig()
    public var gazePitchWindow = 12.0
    public var gazeYawWindow = 20.0
    public init() {}
}

/// Angles are degrees relative to the unmirrored, upright camera image.
/// An invalid sample is distinct from a successfully analyzed frame with no face.
public enum FaceIssue: String {
    case lowLight = "画面太暗"
    case multipleFaces = "检测到多张脸，暂停判断"
    case lowConfidence = "人脸识别置信度不足"
    case missingAngles = "头部角度缺失"
    case inferenceFailed = "Vision 暂时无法分析"
    case noFrame = "暂无有效画面"
}

public struct FaceState {
    public let faceDetected: Bool
    public let pitch: Double?
    public let yaw: Double?
    public let roll: Double?
    public let valid: Bool
    public let eyes: EyePair?
    public let issue: FaceIssue?
    public let faceCount: Int?
    public let confidence: Double?
    public init(faceDetected: Bool, pitch: Double? = nil, yaw: Double? = nil,
                roll: Double? = nil, valid: Bool = true, eyes: EyePair? = nil,
                issue: FaceIssue? = nil, faceCount: Int? = nil, confidence: Double? = nil) {
        self.faceDetected = faceDetected
        self.pitch = pitch
        self.yaw = yaw
        self.roll = roll
        self.valid = valid
        self.eyes = eyes
        self.issue = issue; self.faceCount = faceCount; self.confidence = confidence
    }
    public static let unavailable = FaceState(faceDetected: false, valid: false, issue: .noFrame)
}

public enum AttentionState: String {
    case calibrating, focused, suspected, distracted, away, returning, unknown
}

public enum ReminderSource: String { case head = "头部偏离", gaze = "视线偏离", away = "持续无脸" }

public final class AttentionEngine {
    public let config: AttentionConfig
    public let gaze: AttentionGaze
    public private(set) var reminderSource: ReminderSource?
    public private(set) var state: AttentionState = .calibrating
    public private(set) var alertVisible = false
    public private(set) var baselinePitch: Double?
    public private(set) var baselineYaw: Double?
    public private(set) var baselineRoll: Double?
    private var calibration: [(Double, Double, Double?)] = []
    private var calibrationSince: Double?
    private var observationSince: Double?
    private var initialBaseline: (pitch: Double, yaw: Double)?
    private var adaptationSince: Double?
    private var adaptationRange: (minPitch: Double, maxPitch: Double, minYaw: Double, maxYaw: Double)?
    private var smoothed: (pitch: Double, yaw: Double)?
    private var abnormalSince: Double?
    private var missingSince: Double?
    private var returningSince: Double?
    private var lastTime: Double?
    private var cooldownUntil = -Double.infinity

    public init(config: AttentionConfig = AttentionConfig()) {
        self.config = config; gaze = AttentionGaze(config: config.gaze)
    }

    /// Read-only explanation of the same evidence used by production reminders.
    /// No independent camera, classifier, stored frames or altered timer is involved.
    public func diagnosticText(for sample: FaceState) -> String {
        func number(_ value: Double?) -> String {
            guard let value, value.isFinite else { return "—" }
            return String(format: "%.1f", value)
        }
        let dp = smoothed.flatMap { smooth in baselinePitch.map { abs(smooth.pitch - $0) } }
        let dy = smoothed.flatMap { smooth in baselineYaw.map { abs(smooth.yaw - $0) } }
        let now = lastTime ?? 0
        let deviation = abnormalSince.map { max(0, now - $0) } ?? 0
        let missing = missingSince.map { max(0, now - $0) } ?? 0
        let cooldown = max(0, cooldownUntil - now)
        let reason: String
        if !sample.valid { reason = sample.issue?.rawValue ?? "识别不可靠，暂停判断" }
        else if !sample.faceDetected {
            reason = baselinePitch == nil ? "尚未建立坐姿基准，正在等你入镜" : "没有检测到人脸，正在累计离席时间"
        } else if sample.pitch?.isFinite != true || sample.yaw?.isFinite != true {
            reason = "头部角度缺失，暂停判断"
        } else if baselinePitch == nil { reason = "正在自动适应坐姿，尚未开始判断偏离" }
        else if state == .returning { reason = "已接近坐姿基准，等待稳定后收起提醒" }
        else if alertVisible { reason = "已触发提醒：\(reminderSource?.rawValue ?? "持续偏离")" }
        else if cooldown > 0 { reason = "提醒冷却中，暂不重复提醒" }
        else if abnormalSince != nil { reason = "头部偏离已超过阈值，等待持续满 \(number(config.distractionDuration)) 秒" }
        else if gaze.isAway { reason = "视线偏离正在累计，等待有效信号满 \(number(gaze.config.distractionDuration)) 秒" }
        else { reason = "头部偏离未超过阈值；\(gaze.summary)" }
        func precise(_ value: Double?) -> String { value.map { String(format: "%+.3f", $0) } ?? "—" }
        return """
        \(reason)

        当前角度    俯仰 \(number(sample.pitch))°    左右 \(number(sample.yaw))°
        坐姿基准    俯仰 \(number(baselinePitch))°    左右 \(number(baselineYaw))°
        平滑后偏离  俯仰 \(number(dp))° / >\(number(config.pitchThreshold))°
                    左右 \(number(dy))° / >\(number(config.yawThreshold))°

        眼部状态    \(gaze.summary)
        瞳孔偏移    左 Δy \(precise(gaze.leftDelta?.y))  右 Δy \(precise(gaze.rightDelta?.y))
                    左 Δx \(precise(gaze.leftDelta?.x))  右 Δx \(precise(gaze.rightDelta?.x))
        眼部阈值    y \(precise(gaze.verticalThreshold))  x \(precise(gaze.horizontalThreshold))
        视线偏离    \(number(gaze.awayDuration)) / \(number(gaze.config.distractionDuration)) 秒（有效信号）
        连续偏离    \(number(deviation)) / \(number(config.distractionDuration)) 秒（头部）
        连续无脸    \(number(missing)) / \(number(config.awayDuration)) 秒
        提醒冷却    \(number(cooldown)) 秒
        人脸数量    \(sample.faceCount.map(String.init) ?? "—")    置信度 \(number(sample.confidence.map { $0 * 100 }))%
        """
    }

    public func reset() {
        baselinePitch = nil; baselineYaw = nil; baselineRoll = nil
        calibration.removeAll(); calibrationSince = nil; observationSince = nil
        initialBaseline = nil
        clearContinuity(); lastTime = nil; cooldownUntil = -.infinity
        state = .calibrating; alertVisible = false
        gaze.reset(); reminderSource = nil
    }

    private func clearContinuity() {
        abnormalSince = nil; missingSince = nil; returningSince = nil; smoothed = nil
        gaze.invalidate()
        resetAdaptation()
    }

    private func resetAdaptation() {
        adaptationSince = nil; adaptationRange = nil
    }

    private func unknown() {
        clearContinuity(); calibration.removeAll(); calibrationSince = nil; observationSince = nil
        gaze.clearCalibrationSamples(); reminderSource = nil
        alertVisible = false; state = .unknown
    }

    /// Pass monotonic seconds. Missing/invalid data must never accrue distraction time.
    @discardableResult public func update(_ sample: FaceState, at time: Double) -> AttentionState {
        guard time.isFinite else { unknown(); return state }
        if let lastTime, time <= lastTime { return state }
        let interval = lastTime.map { min(time - $0, config.maximumSampleGap) } ?? 0
        if let lastTime, time - lastTime > config.maximumSampleGap { unknown() }
        lastTime = time
        guard sample.valid else { unknown(); return state }
        if !sample.faceDetected {
            smoothed = nil; abnormalSince = nil; returningSince = nil
            gaze.invalidate(reason: .noFace); gaze.clearCalibrationSamples()
            resetAdaptation()
            guard baselinePitch != nil else {
                calibration.removeAll(); calibrationSince = nil; observationSince = nil
                state = .calibrating; return state
            }
            missingSince = missingSince ?? time
            let duration = time - missingSince!
            if duration >= config.awayDuration {
                state = .away
                if time >= cooldownUntil { alertVisible = true; reminderSource = .away }
            } else if alertVisible || duration >= config.missingSuspectedDuration {
                state = .suspected
            } else { state = .unknown }
            return state
        }
        missingSince = nil
        guard let pitch = sample.pitch, let yaw = sample.yaw,
              pitch.isFinite, yaw.isFinite else { unknown(); return state }

        if baselinePitch == nil {
            state = .calibrating
            observationSince = observationSince ?? time
            // Startup is observation, not proof of looking at the screen. Delay commitment
            // so a short initial glance can finish, then require a stable current pose.
            if calibration.contains(where: {
                abs($0.0 - pitch) > config.calibrationTolerance || abs($0.1 - yaw) > config.calibrationTolerance
            }) {
                calibration.removeAll(); calibrationSince = nil
                gaze.clearCalibrationSamples()
            }
            calibrationSince = calibrationSince ?? time
            calibration.append((pitch, yaw, sample.roll))
            gaze.collectBaseline(sample.eyes, at: time)
            // Bound memory while waiting for the startup observation period.
            if calibration.count > 128 { calibration.removeFirst() }
            if time - observationSince! >= config.startupObservationDuration,
               time - calibrationSince! >= config.calibrationDuration,
               calibration.count >= config.calibrationMinimumSamples {
                baselinePitch = calibration.map { $0.0 }.reduce(0, +) / Double(calibration.count)
                baselineYaw = calibration.map { $0.1 }.reduce(0, +) / Double(calibration.count)
                initialBaseline = (baselinePitch!, baselineYaw!)
                let rolls = calibration.compactMap { $0.2 }.filter(\.isFinite)
                baselineRoll = rolls.isEmpty ? nil : rolls.reduce(0, +) / Double(rolls.count)
                calibration.removeAll(); smoothed = (pitch, yaw); state = .focused
                gaze.finishCalibration()
            }
            return state
        }
        let alpha = config.smoothingAlpha
        let previous = smoothed ?? (pitch, yaw)
        let smooth = (pitch: alpha * pitch + (1 - alpha) * previous.0,
                      yaw: alpha * yaw + (1 - alpha) * previous.1)
        smoothed = smooth
        // Eye geometry changes with perspective. Trust its startup reference only
        // near the same head pose; large turns continue to use head-pose detection.
        let nearEyeReference = initialBaseline.map {
            abs(pitch - $0.pitch) <= config.gazePitchWindow && abs(yaw - $0.yaw) <= config.gazeYawWindow
        } ?? false
        let rollReliable = baselineRoll.flatMap { base in sample.roll.map { abs($0 - base) < 15 } } ?? true
        let eyeIssue: EyeSignalIssue? = !nearEyeReference ? .headPose : (!rollReliable ? .headRoll : nil)
        gaze.update(eyeIssue == nil ? sample.eyes : nil, at: time, unavailableReason: eyeIssue)
        let dp = abs(smooth.pitch - baselinePitch!), dy = abs(smooth.yaw - baselineYaw!)
        let abnormal = dp > config.pitchThreshold || dy > config.yawThreshold
        let eyesReturned = gaze.direction == .center || (!gaze.calibrated || gaze.direction == .unavailable) && reminderSource != .gaze
        let returned = dp < config.returnPitchThreshold && dy < config.returnYawThreshold && eyesReturned

        if alertVisible, reminderSource == .gaze, !abnormal, gaze.direction == .unavailable,
           time - (gaze.lastReliableTime ?? -.infinity) > gaze.config.blinkGrace {
            // Do not leave an eye-only warning stuck on screen after glasses glare
            // or occlusion. This is uncertainty, not evidence of a successful return.
            alertVisible = false; reminderSource = nil; returningSince = nil; state = .unknown
            resetAdaptation(); return state
        }

        if alertVisible {
            if returned {
                returningSince = returningSince ?? time
                state = .returning
                if time - returningSince! >= config.returnDuration {
                    alertVisible = false; state = .focused
                    cooldownUntil = time + config.reminderCooldown
                    abnormalSince = nil; returningSince = nil
                    reminderSource = nil
                }
            } else { returningSince = nil; state = .distracted }
        } else {
            returningSince = nil
            abnormalSince = abnormal ? abnormalSince ?? time : nil
            let duration = abnormalSince.map { time - $0 } ?? 0
            state = duration >= config.suspectedDuration || gaze.awayDuration >= config.suspectedDuration ? .suspected : .focused
            if (duration >= config.distractionDuration || gaze.canRemind) && time >= cooldownUntil {
                state = .distracted; alertVisible = true
                reminderSource = duration >= config.distractionDuration ? .head : .gaze
            }
        }
        adaptBaseline(pitch: pitch, yaw: yaw, at: time, interval: interval)
        return state
    }

    private func adaptBaseline(pitch: Double, yaw: Double, at time: Double, interval: Double) {
        guard state == .focused, !alertVisible, abnormalSince == nil, !gaze.isAway,
              let basePitch = baselinePitch, let baseYaw = baselineYaw, let initialBaseline,
              abs(pitch - basePitch) <= config.adaptationPitchWindow,
              abs(yaw - baseYaw) <= config.adaptationYawWindow else {
            resetAdaptation(); return
        }
        let previous = adaptationRange ?? (pitch, pitch, yaw, yaw)
        let range = (minPitch: min(previous.0, pitch), maxPitch: max(previous.1, pitch),
                     minYaw: min(previous.2, yaw), maxYaw: max(previous.3, yaw))
        if range.maxPitch - range.minPitch > config.adaptationTolerance ||
           range.maxYaw - range.minYaw > config.adaptationTolerance {
            adaptationSince = time; adaptationRange = (pitch, pitch, yaw, yaw); return
        }
        adaptationRange = range; adaptationSince = adaptationSince ?? time
        guard time - adaptationSince! >= config.adaptationStableDuration else { return }
        // Adapt only nearby stable poses, with a fixed cap relative to the startup anchor.
        // Repeated small movements must never ratchet the baseline into a sustained turn.
        let alpha = 1 - exp(-interval / max(0.001, config.adaptationTimeConstant))
        let cap = config.adaptationMaximumDrift
        baselinePitch = max(initialBaseline.pitch - cap, min(initialBaseline.pitch + cap,
                            basePitch + alpha * (pitch - basePitch)))
        baselineYaw = max(initialBaseline.yaw - cap, min(initialBaseline.yaw + cap,
                          baseYaw + alpha * (yaw - baseYaw)))
    }
}
