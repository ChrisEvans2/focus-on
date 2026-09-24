import Foundation

public struct EyePoint: Equatable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct EyeMeasurement {
    /// Eye-local coordinates: x increases toward image-right; y increases downward.
    public let pupil: EyePoint
    public let contour: [EyePoint]
    public let openness: Double
    public init(pupil: EyePoint, contour: [EyePoint], openness: Double) {
        self.pupil = pupil; self.contour = contour; self.openness = openness
    }
}

public enum EyeGeometry {
    /// Input coordinates must be aspect-correct image pixels, with y increasing upward.
    /// The longest contour chord approximates the eye corners, removing in-plane head roll.
    public static func measure(contour: [EyePoint], pupil: EyePoint?) -> EyeMeasurement? {
        guard contour.count >= 6, let pupil,
              (contour + [pupil]).allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        var ends = (contour[0], contour[1]), longest = 0.0
        for i in contour.indices {
            for j in contour.indices where j > i {
                let d = hypot(contour[j].x - contour[i].x, contour[j].y - contour[i].y)
                if d > longest { longest = d; ends = (contour[i], contour[j]) }
            }
        }
        guard longest >= 12 else { return nil }
        if ends.0.x > ends.1.x { ends = (ends.1, ends.0) }
        let ux = (ends.1.x - ends.0.x) / longest, uy = (ends.1.y - ends.0.y) / longest
        // Extreme in-plane rotation is too ambiguous for this approximate test.
        guard ux >= 0.5 else { return nil }
        func project(_ point: EyePoint) -> EyePoint {
            let x = point.x - ends.0.x, y = point.y - ends.0.y
            return EyePoint(x: x * ux + y * uy, y: -x * uy + y * ux)
        }
        let projected = contour.map(project)
        let low = projected.map(\.y).min()!, high = projected.map(\.y).max()!
        let height = high - low, openness = height / longest
        guard openness >= 0.10, openness <= 0.75 else { return nil }
        func normalize(_ p: EyePoint) -> EyePoint { EyePoint(x: p.x / longest, y: (high - p.y) / height) }
        let normalizedPupil = normalize(project(pupil))
        guard (-0.1...1.1).contains(normalizedPupil.x), (-0.15...1.15).contains(normalizedPupil.y) else { return nil }
        return EyeMeasurement(pupil: normalizedPupil, contour: projected.map(normalize), openness: openness)
    }
}

public struct EyePair {
    public let left: EyeMeasurement?
    public let right: EyeMeasurement?
    public init(left: EyeMeasurement?, right: EyeMeasurement?) { self.left = left; self.right = right }
    public var center: EyePoint? {
        guard let left, let right,
              abs(left.pupil.x - right.pupil.x) < 0.25,
              abs(left.pupil.y - right.pupil.y) < 0.35 else { return nil }
        return EyePoint(x: (left.pupil.x + right.pupil.x) / 2, y: (left.pupil.y + right.pupil.y) / 2)
    }
}

public struct GazeReference {
    public let point: EyePoint
    public let noise: EyePoint
    public let sampleCount: Int
    public init?(samples: [EyePoint]) {
        guard samples.count >= 8, samples.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let n = Double(samples.count)
        let x = samples.map(\.x).reduce(0, +) / n, y = samples.map(\.y).reduce(0, +) / n
        point = EyePoint(x: x, y: y)
        noise = EyePoint(x: sqrt(samples.map { pow($0.x - x, 2) }.reduce(0, +) / n),
                         y: sqrt(samples.map { pow($0.y - y, 2) }.reduce(0, +) / n))
        sampleCount = samples.count
    }
    public var stable: Bool { noise.x < 0.10 && noise.y < 0.12 }
    public func separatesVertically(from reference: GazeReference) -> Bool {
        stable && reference.stable && abs(point.y - reference.point.y) > max(0.08, 3 * max(noise.y, reference.noise.y))
    }
}

public enum ApproximateGaze: String {
    case unavailable, uncalibrated, center, down, up, left, right
}

/// Experimental display-only estimator. It deliberately has no connection to AttentionEngine.
public final class GazeEstimator {
    public private(set) var reference: GazeReference?
    public private(set) var direction: ApproximateGaze = .uncalibrated
    public private(set) var delta: EyePoint?
    private var smooth: EyePoint?
    private var lastTime: Double?
    private var candidate: ApproximateGaze = .unavailable
    private var candidateSince = 0.0
    public init() {}
    public func calibrate(_ reference: GazeReference) {
        guard reference.stable else { return }
        self.reference = reference; clearSignal(); direction = .center
    }
    public func reset() { reference = nil; clearSignal(); direction = .uncalibrated }
    private func clearSignal() { smooth = nil; delta = nil; candidate = .unavailable; lastTime = nil }
    @discardableResult public func update(_ eyes: EyePair?, at time: Double) -> ApproximateGaze {
        guard time.isFinite else { clearSignal(); direction = .unavailable; return direction }
        if let lastTime, time <= lastTime { return direction }
        if let lastTime, time - lastTime > 0.7 { clearSignal(); direction = .unavailable }
        lastTime = time
        guard let point = eyes?.center else {
            clearSignal(); lastTime = time; direction = .unavailable; return direction
        }
        guard let reference else { direction = .uncalibrated; return direction }
        let old = smooth ?? point
        let filtered = EyePoint(x: 0.35 * point.x + 0.65 * old.x, y: 0.35 * point.y + 0.65 * old.y)
        smooth = filtered
        let diff = EyePoint(x: filtered.x - reference.point.x, y: filtered.y - reference.point.y)
        delta = diff
        let horizontal = max(0.12, 3 * reference.noise.x), vertical = max(0.12, 3 * reference.noise.y)
        let next: ApproximateGaze
        if abs(diff.y) / vertical > max(1, abs(diff.x) / horizontal) { next = diff.y > 0 ? .down : .up }
        // The camera is not mirrored: image-right is the user's left.
        else if abs(diff.x) > horizontal { next = diff.x > 0 ? .left : .right }
        else { next = .center }
        if next != candidate { candidate = next; candidateSince = time }
        if time - candidateSince >= 0.4 { direction = candidate }
        return direction
    }
}
