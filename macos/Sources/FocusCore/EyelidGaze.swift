import Foundation

public enum EyeSignalIssue: String {
    case interrupted = "眼部数据暂不可用"
    case missingPoints = "眼睛或瞳孔点位缺失"
    case invalidGeometry = "眼部几何数据未通过检查"
    case smallAperture = "眼部开口过小，暂停判断"
    case narrowRelativeToBaseline = "开合度低于基准一半，暂停判断"
    case disagreement = "双眼测量差异过大"
    case headPose = "头部角度超出眼部参考范围"
    case headRoll = "头部侧倾超出眼部参考范围"
    case noFace = "未检测到人脸"
}

/// Experimental cue: aperture height / eye width, relative to each eye's startup mean.
/// Squinting and deliberately widening the eyes remain ambiguous; this is not gaze truth.
public final class EyelidGaze {
    public private(set) var reference: GazeReference?
    /// x = left eye, y = right eye; +0.2 means 20% more open than at startup.
    public private(set) var change: EyePoint?
    public private(set) var direction: ApproximateGaze = .uncalibrated
    public private(set) var unavailableReason: EyeSignalIssue?
    public let minimumChange = 0.20
    public let confirmationDuration = 0.8
    private var smoothed: EyePoint?
    private var candidate: ApproximateGaze?
    private var since: Double?
    private var lastTime: Double?

    public var thresholds: EyePoint? {
        guard let reference else { return nil }
        return EyePoint(x: max(minimumChange, 3 * reference.noise.x / reference.point.x),
                        y: max(minimumChange, 3 * reference.noise.y / reference.point.y))
    }

    func calibrate(_ samples: [EyePoint]) {
        reset()
        guard let value = GazeReference(samples: samples),
              value.point.x >= 0.12, value.point.y >= 0.12,
              value.noise.x / value.point.x <= 0.10,
              value.noise.y / value.point.y <= 0.10 else { return }
        reference = value; direction = .center
        unavailableReason = nil
    }

    func reset() { reference = nil; invalidate(); direction = .uncalibrated }

    func invalidate(reason: EyeSignalIssue = .interrupted) {
        change = nil; smoothed = nil; candidate = nil; since = nil; lastTime = nil
        direction = reference == nil ? .uncalibrated : .unavailable
        unavailableReason = reference == nil ? nil : reason
    }

    func update(left: Double, right: Double, at time: Double, alpha: Double, maximumGap: Double) {
        guard let reference, let thresholds else { return }
        guard time.isFinite, left.isFinite, right.isFinite,
              (0.12...0.75).contains(left), (0.12...0.75).contains(right) else {
            invalidate(reason: .invalidGeometry); return
        }
        guard left / reference.point.x > 0.3, right / reference.point.y > 0.3 else {
            invalidate(reason: .narrowRelativeToBaseline); return
        }
        if let lastTime {
            guard time > lastTime else { return }
            if time - lastTime > maximumGap { invalidate() }
        }
        lastTime = time
        unavailableReason = nil
        let current = EyePoint(x: left / reference.point.x - 1, y: right / reference.point.y - 1)
        let old = smoothed ?? current
        let value = EyePoint(x: alpha * current.x + (1 - alpha) * old.x,
                             y: alpha * current.y + (1 - alpha) * old.y)
        smoothed = value; change = value
        let next: ApproximateGaze
        if value.x < -thresholds.x && value.y < -thresholds.y { next = .down }
        else if value.x > thresholds.x && value.y > thresholds.y { next = .up }
        else { next = .center }
        guard next != .center else { candidate = nil; since = nil; direction = .center; return }
        if candidate != next { candidate = next; since = time }
        direction = time - (since ?? time) >= confirmationDuration ? next : .center
    }

    public var diagnosticText: String {
        func percent(_ value: Double?) -> String { value.map { String(format: "%+.0f%%", $0 * 100) } ?? "—" }
        func number(_ value: Double?) -> String { value.map { String(format: "%.3f", $0) } ?? "—" }
        let state: String
        switch direction {
        case .up: state = "双眼开大：疑似向上"
        case .down: state = "双眼收窄：疑似向下"
        case .unavailable: state = unavailableReason?.rawValue ?? EyeSignalIssue.interrupted.rawValue
        case .uncalibrated: state = "基准不足或开合波动太大"
        default: state = candidate == nil ? "未见一致变化" : "变化持续不足 0.8 秒"
        }
        return """
        眼睑辅助    \(state)
        开合基准    左 \(number(reference?.point.x))  右 \(number(reference?.point.y))
        开合变化    左 \(percent(change?.x))  右 \(percent(change?.y))
        开合阈值    左 ±\(percent(thresholds?.x).replacingOccurrences(of: "+", with: ""))  右 ±\(percent(thresholds?.y).replacingOccurrences(of: "+", with: ""))
        """
    }
}
