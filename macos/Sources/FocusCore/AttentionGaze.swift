import Foundation

public struct AttentionGazeConfig {
    public var calibrationDuration = 1.5
    public var minimumSamples = 10
    public var maximumNoise = 0.05
    public var verticalThreshold = 0.08
    public var horizontalThreshold = 0.10
    public var noiseMultiplier = 3.0
    public var returnRatio = 0.6
    public var smoothingAlpha = 0.65
    public var blinkGrace = 0.6
    public var distractionDuration = 10.0
    public var minimumValidFraction = 0.8
    public var eyelidAssistanceEnabled = false
    public init() {}
}

/// Relative pupil direction, not a screen coordinate or proof of phone use.
/// Each eye must independently support the direction. Baselines are collected only
/// alongside startup head-pose calibration, never learned from a later downward stare.
public final class AttentionGaze {
    public let config: AttentionGazeConfig
    public private(set) var leftReference: GazeReference?
    public private(set) var rightReference: GazeReference?
    public private(set) var direction: ApproximateGaze = .uncalibrated
    public private(set) var leftDelta: EyePoint?
    public private(set) var rightDelta: EyePoint?
    public let eyelids = EyelidGaze()
    public private(set) var usingEyelids = false
    public private(set) var unavailableReason: EyeSignalIssue?
    public private(set) var awayDuration = 0.0
    public private(set) var lastReliableTime: Double?
    public var calibrated: Bool { leftReference != nil && rightReference != nil }
    public var verticalThreshold: Double? {
        guard let leftReference, let rightReference else { return nil }
        return max(config.verticalThreshold, config.noiseMultiplier * max(leftReference.noise.y, rightReference.noise.y))
    }
    public var horizontalThreshold: Double? {
        guard let leftReference, let rightReference else { return nil }
        return max(config.horizontalThreshold, config.noiseMultiplier * max(leftReference.noise.x, rightReference.noise.x))
    }
    public var isAway: Bool { [.down, .up, .left, .right].contains(direction) }
    public var canRemind: Bool {
        guard isAway, awayDuration >= config.distractionDuration, let awaySince, let lastTime else { return false }
        return awayDuration / max(0.001, lastTime - awaySince) >= config.minimumValidFraction
    }
    private var samples: [(time: Double, left: EyePoint, right: EyePoint, openness: EyePoint)] = []
    private var smoothLeft: EyePoint?
    private var smoothRight: EyePoint?
    private var lastTime: Double?
    private var previousWasAway = false
    private var awaySince: Double?
    private var evidenceDirection: ApproximateGaze?

    public init(config: AttentionGazeConfig = AttentionGazeConfig()) { self.config = config }

    private func measurementIssue(_ eyes: EyePair?) -> EyeSignalIssue? {
        guard let eyes, let left = eyes.left, let right = eyes.right else { return .missingPoints }
        for eye in [left, right] {
            guard eye.pupil.x.isFinite, eye.pupil.y.isFinite, eye.openness.isFinite,
                  (-0.1...1.1).contains(eye.pupil.x), (-0.15...1.15).contains(eye.pupil.y),
                  (0...0.75).contains(eye.openness) else { return .invalidGeometry }
            if eye.openness < 0.12 { return .smallAperture }
        }
        return eyes.center == nil ? .disagreement : nil
    }

    private func usable(_ eyes: EyePair?) -> (EyeMeasurement, EyeMeasurement)? {
        guard measurementIssue(eyes) == nil, let left = eyes?.left, let right = eyes?.right else { return nil }
        return (left, right)
    }

    public func clearCalibrationSamples() { samples.removeAll() }

    public func collectBaseline(_ eyes: EyePair?, at time: Double) {
        guard time.isFinite else { clearCalibrationSamples(); return }
        guard let (left, right) = usable(eyes) else {
            if time - (samples.last?.time ?? -.infinity) > config.blinkGrace { clearCalibrationSamples() }
            return
        }
        if let last = samples.last {
            guard time > last.time else { return }
            if time - last.time > config.blinkGrace { clearCalibrationSamples() }
        }
        // Only the recent stable pose is a candidate, not every gaze during startup.
        samples.removeAll { time - $0.time > 2.5 }
        samples.append((time, left.pupil, right.pupil, EyePoint(x: left.openness, y: right.openness)))
        if samples.count > 64 { samples.removeFirst() }
    }

    public func finishCalibration() {
        defer { clearCalibrationSamples() }
        eyelids.reset()
        guard samples.count >= config.minimumSamples, let first = samples.first, let last = samples.last,
              last.time - first.time >= config.calibrationDuration,
              let left = GazeReference(samples: samples.map(\.left)),
              let right = GazeReference(samples: samples.map(\.right)),
              [left.noise.x, left.noise.y, right.noise.x, right.noise.y].allSatisfy({ $0 <= config.maximumNoise }) else {
            direction = .uncalibrated; return
        }
        leftReference = left; rightReference = right; direction = .center
        unavailableReason = nil
        if config.eyelidAssistanceEnabled { eyelids.calibrate(samples.map(\.openness)) }
    }

    public func reset() {
        leftReference = nil; rightReference = nil; clearCalibrationSamples()
        eyelids.reset()
        invalidate(); lastTime = nil; direction = .uncalibrated; unavailableReason = nil
    }

    /// Long gaps must not join two unrelated runs of evidence.
    public func invalidate(reason: EyeSignalIssue = .interrupted) {
        smoothLeft = nil; smoothRight = nil; leftDelta = nil; rightDelta = nil
        eyelids.invalidate(reason: reason); usingEyelids = false; unavailableReason = reason
        clearEvidence(); lastReliableTime = nil; direction = .unavailable
    }

    private func clearEvidence() {
        awayDuration = 0; awaySince = nil; previousWasAway = false; evidenceDirection = nil
    }

    public func update(_ eyes: EyePair?, at time: Double, unavailableReason: EyeSignalIssue? = nil) {
        guard time.isFinite else { invalidate(); return }
        if let lastTime, time <= lastTime { return }
        let interval = lastTime.map { time - $0 } ?? 0
        if interval > config.blinkGrace { invalidate() }
        lastTime = time
        usingEyelids = false
        guard calibrated else { direction = .uncalibrated; return }
        guard let (left, right) = usable(eyes) else {
            let reason = unavailableReason ?? measurementIssue(eyes) ?? .interrupted
            self.unavailableReason = reason; eyelids.invalidate(reason: reason)
            direction = .unavailable; leftDelta = nil; rightDelta = nil
            previousWasAway = false
            if time - (lastReliableTime ?? -.infinity) > config.blinkGrace { invalidate(reason: reason) }
            return
        }
        self.unavailableReason = nil
        func smooth(_ value: EyePoint, _ old: EyePoint?) -> EyePoint {
            guard let old else { return value }
            let a = config.smoothingAlpha
            return EyePoint(x: a * value.x + (1 - a) * old.x, y: a * value.y + (1 - a) * old.y)
        }
        let l = smooth(left.pupil, smoothLeft), r = smooth(right.pupil, smoothRight)
        smoothLeft = l; smoothRight = r
        let lr = leftReference!, rr = rightReference!
        let ld = EyePoint(x: l.x - lr.point.x, y: l.y - lr.point.y)
        let rd = EyePoint(x: r.x - rr.point.x, y: r.y - rr.point.y)
        leftDelta = ld; rightDelta = rd; lastReliableTime = time
        if config.eyelidAssistanceEnabled {
            eyelids.update(left: left.openness, right: right.openness, at: time,
                           alpha: config.smoothingAlpha, maximumGap: config.blinkGrace)
        }
        let hx = horizontalThreshold!, vy = verticalThreshold!
        let retain = config.returnRatio
        let next: ApproximateGaze
        // Hysteresis applies to an already established direction, never to a new one.
        if min(ld.y, rd.y) > vy * (evidenceDirection == .down ? retain : 1) { next = .down }
        else if max(ld.y, rd.y) < -vy * (evidenceDirection == .up ? retain : 1) { next = .up }
        else if min(ld.x, rd.x) > hx * (evidenceDirection == .left ? retain : 1) { next = .left }
        else if max(ld.x, rd.x) < -hx * (evidenceDirection == .right ? retain : 1) { next = .right }
        else if config.eyelidAssistanceEnabled,
                abs(ld.y) < vy, abs(rd.y) < vy, abs(ld.x) < hx, abs(rd.x) < hx,
                eyelids.direction == .up || eyelids.direction == .down {
            // Preserve pupil-based horizontal/vertical decisions; only fill an inconclusive result.
            next = eyelids.direction; usingEyelids = true
        }
        else { next = .center }
        direction = next
        if isAway {
            if evidenceDirection != next {
                clearEvidence(); evidenceDirection = next; awaySince = time
            }
            if previousWasAway { awayDuration += interval }
            previousWasAway = true
        } else { clearEvidence() }
    }

    public var summary: String {
        guard calibrated else { return "眼部基准不足，仅用头部判断" }
        switch direction {
        case .unavailable: return "\(unavailableReason?.rawValue ?? EyeSignalIssue.interrupted.rawValue)，仅用头部判断"
        case .uncalibrated: return "眼部基准不足，仅用头部判断"
        case .center: return "接近视线基准（估计）"
        case .down: return usingEyelids ? "疑似向下（眼睑辅助）" : "向下看（估计）"
        case .up: return usingEyelids ? "疑似向上（眼睑辅助）" : "向上看（估计）"
        case .left: return "向左看（估计）"
        case .right: return "向右看（估计）"
        }
    }
}
