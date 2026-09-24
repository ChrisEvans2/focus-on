import Foundation

public struct FocusPhase: Codable {
    public let kind: String
    public let seconds: Double
    public init(kind: String, seconds: Double) { self.kind = kind; self.seconds = seconds }
}

/// Native deadline evaluation remains active when WebKit timers are throttled.
public struct FocusSchedule: Codable {
    public let running: Bool
    public let startedAt: Double?
    public let elapsed: Double
    public let phases: [FocusPhase]
    public let monitoring: Bool
    public let sessionId: String?

    public init(running: Bool, startedAt: Double?, elapsed: Double,
                phases: [FocusPhase], monitoring: Bool, sessionId: String? = nil) {
        self.running = running; self.startedAt = startedAt; self.elapsed = elapsed
        self.phases = phases; self.monitoring = monitoring
        self.sessionId = sessionId
    }
    public var isValid: Bool {
        elapsed.isFinite && elapsed >= 0 && elapsed <= 7200 &&
        (!running || (startedAt?.isFinite == true)) &&
        !phases.isEmpty && phases.count <= 9 &&
        phases.allSatisfy { ["focus", "break"].contains($0.kind) && $0.seconds.isFinite && $0.seconds > 0 } &&
        phases.reduce(0) { $0 + $1.seconds } <= 7200
    }
    public func phase(at epochSeconds: Double) -> String? {
        guard isValid, running, let startedAt else { return nil }
        var remaining = elapsed + max(0, epochSeconds - startedAt)
        for phase in phases {
            if remaining < phase.seconds { return phase.kind }
            remaining -= phase.seconds
        }
        return nil
    }
    public func shouldMonitor(at epochSeconds: Double) -> Bool {
        monitoring && phase(at: epochSeconds) == "focus"
    }
}
