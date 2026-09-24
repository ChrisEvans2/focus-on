import Foundation
import FocusCore

final class EyelidGazeTests {
    var time = 0.0
    func pair(_ left: Double = 0.30, _ right: Double = 0.30, x: Double = 0.5, y: Double = 0.5) -> EyePair {
        func eye(_ height: Double) -> EyeMeasurement? {
            let half = 40 * height / 2
            let contour = [EyePoint(x: 0, y: 0), EyePoint(x: 10, y: half), EyePoint(x: 30, y: half),
                           EyePoint(x: 40, y: 0), EyePoint(x: 30, y: -half), EyePoint(x: 10, y: -half)]
            return EyeGeometry.measure(contour: contour, pupil: EyePoint(x: x * 40, y: half - y * 2 * half))
        }
        return EyePair(left: eye(left), right: eye(right))
    }
    func make(enabled: Bool = true) -> AttentionGaze {
        var config = AttentionGazeConfig(); config.eyelidAssistanceEnabled = enabled
        let gaze = AttentionGaze(config: config)
        for i in 0...20 { gaze.collectBaseline(pair(), at: Double(i) / 10) }
        gaze.finishCalibration(); time = 2
        return gaze
    }
    func feed(_ gaze: AttentionGaze, _ eyes: EyePair?, seconds: Double) {
        for _ in 0..<Int((seconds * 10).rounded()) { time += 0.1; gaze.update(eyes, at: time) }
    }

    func testSustainedOpennessFindsVerticalMotionWithStationaryNormalizedPupils() {
        let gaze = make()
        feed(gaze, pair(0.21, 0.21), seconds: 0.5)
        expectEqual(gaze.direction, .center); expectEqual(gaze.awayDuration, 0, accuracy: 0.001)
        feed(gaze, pair(0.21, 0.21), seconds: 0.6)
        expectEqual(gaze.direction, .down); expectTrue(gaze.usingEyelids)
        expectEqual(gaze.leftDelta!.y, 0, accuracy: 0.001)
        expectEqual(gaze.eyelids.change!.x, -0.30, accuracy: 0.001)
        feed(gaze, pair(), seconds: 0.5)
        expectEqual(gaze.direction, .center)
        feed(gaze, pair(0.39, 0.39), seconds: 1.4)
        expectEqual(gaze.direction, .up); expectTrue(gaze.usingEyelids)
    }

    func testBriefNarrowingBlinksAndMissingFramesDoNotJoin() {
        let gaze = make()
        for _ in 0..<8 {
            feed(gaze, pair(0.21, 0.21), seconds: 0.3)
            feed(gaze, pair(), seconds: 0.5)
            expectEqual(gaze.direction, .center)
        }
        expectFalse(gaze.canRemind)
        feed(gaze, pair(0.21, 0.21), seconds: 0.5)
        feed(gaze, nil, seconds: 0.1)
        expectEqual(gaze.eyelids.unavailableReason, .missingPoints)
        feed(gaze, pair(0.21, 0.21), seconds: 0.5)
        expectEqual(gaze.direction, .center)
        feed(gaze, pair(0.13, 0.13), seconds: 2) // Below half the baseline: near-closure, not downgaze.
        expectEqual(gaze.eyelids.direction, .unavailable)
        expectEqual(gaze.eyelids.unavailableReason, .narrowRelativeToBaseline)
        expectFalse(gaze.usingEyelids); expectFalse(gaze.canRemind)
        time += 2
        feed(gaze, pair(0.21, 0.21), seconds: 0.3)
        expectEqual(gaze.direction, .center)
        expectNil(gaze.eyelids.unavailableReason)
    }

    func testOneEyeAndConflictingPupilsCannotActivateEyelidFallback() {
        let gaze = make()
        feed(gaze, pair(0.21, 0.30), seconds: 2)
        expectEqual(gaze.direction, .center)
        let opposite = EyePair(left: pair(0.21, 0.21, y: 0.4).left,
                               right: pair(0.21, 0.21, y: 0.6).right)
        feed(gaze, opposite, seconds: 2)
        expectFalse(gaze.usingEyelids); expectEqual(gaze.direction, .center)
    }

    func testHorizontalPupilsKeepPriorityAndProductionIsUnchanged() {
        let gaze = make()
        feed(gaze, pair(0.21, 0.21, x: 0.7), seconds: 2)
        expectEqual(gaze.direction, .left); expectFalse(gaze.usingEyelids)
        feed(gaze, pair(0.39, 0.39, x: 0.3), seconds: 2)
        expectEqual(gaze.direction, .right); expectFalse(gaze.usingEyelids)
        let production = make(enabled: false)
        expectFalse(AttentionConfig().gaze.eyelidAssistanceEnabled)
        feed(production, pair(0.21, 0.21), seconds: 15)
        expectEqual(production.direction, .center); expectFalse(production.canRemind)
    }

    func testUnstableLidBaselineDoesNotDisablePupilTrackingAndResetClearsIt() {
        var config = AttentionGazeConfig(); config.eyelidAssistanceEnabled = true
        let gaze = AttentionGaze(config: config)
        for i in 0...20 { gaze.collectBaseline(i % 2 == 0 ? pair(0.21, 0.21) : pair(0.39, 0.39), at: Double(i) / 10) }
        gaze.finishCalibration(); time = 2
        expectTrue(gaze.calibrated); expectNil(gaze.eyelids.reference)
        feed(gaze, pair(x: 0.7), seconds: 1)
        expectEqual(gaze.direction, .left)
        let stable = make(); feed(stable, pair(0.21, 0.21), seconds: 2)
        stable.reset()
        expectNil(stable.eyelids.reference); expectNil(stable.eyelids.change); expectFalse(stable.usingEyelids)
    }

    func testHeadPoseGateAlsoStopsEyelidCue() {
        var config = AttentionConfig(); config.gaze.eyelidAssistanceEnabled = true
        let engine = AttentionEngine(config: config)
        for i in 0...65 { engine.update(FaceState(faceDetected: true, pitch: 0, yaw: 0, roll: 0, eyes: pair()), at: Double(i) / 10) }
        for i in 66...90 { engine.update(FaceState(faceDetected: true, pitch: 0, yaw: 0, roll: 0, eyes: pair(0.21, 0.21)), at: Double(i) / 10) }
        expectTrue(engine.gaze.usingEyelids)
        engine.update(FaceState(faceDetected: true, pitch: 0, yaw: 25, roll: 0, eyes: pair(0.21, 0.21)), at: 9.1)
        expectEqual(engine.gaze.direction, .unavailable); expectNil(engine.gaze.eyelids.change)
        expectFalse(engine.gaze.usingEyelids)
        expectEqual(engine.gaze.unavailableReason, .headPose)
        expectEqual(engine.gaze.eyelids.unavailableReason, .headPose)
        for i in 92...105 {
            engine.update(FaceState(faceDetected: true, pitch: 0, yaw: 25, roll: 0, eyes: pair(0.21, 0.21)), at: Double(i) / 10)
        }
        expectEqual(engine.gaze.eyelids.unavailableReason, .headPose)
        engine.update(FaceState(faceDetected: true, pitch: 0, yaw: 0, roll: 0, eyes: pair()), at: 10.6)
        expectNil(engine.gaze.unavailableReason); expectNil(engine.gaze.eyelids.unavailableReason)
        engine.update(FaceState(faceDetected: false), at: 10.7)
        expectEqual(engine.gaze.eyelids.unavailableReason, .noFace)
    }
}
