import Foundation
import FocusCore

final class AttentionGazeTests {
    let helper = EyeTrackingTests()
    let engine = AttentionEngine()
    var time = 0.0
    func feed(_ eyes: EyePair?, seconds: Double, pitch: Double = 13.7, yaw: Double = 7.9) {
        for _ in 0..<Int((seconds * 10).rounded()) {
            time += 0.1
            engine.update(FaceState(faceDetected: true, pitch: pitch, yaw: yaw, roll: 0, eyes: eyes), at: time)
        }
    }
    func prepare() { feed(helper.pair(), seconds: 6.5); expectTrue(engine.gaze.calibrated) }

    func testShortGlancesAndOneEyeDisagreementNeverAlert() {
        prepare()
        for _ in 0..<6 {
            feed(helper.pair(0.5, 0.7), seconds: 3)
            feed(helper.pair(), seconds: 2)
        }
        expectFalse(engine.alertVisible)
        feed(EyePair(left: helper.eye(0.5, 0.7), right: helper.eye(0.5, 0.45)), seconds: 15)
        expectFalse(engine.alertVisible)
    }

    func testBlinkPausesEvidenceButDoesNotPreventSustainedGazeAlert() {
        prepare()
        feed(helper.pair(0.5, 0.7), seconds: 5)
        let before = engine.gaze.awayDuration
        feed(nil, seconds: 0.3)
        expectEqual(engine.gaze.awayDuration, before, accuracy: 0.001)
        expectFalse(engine.alertVisible)
        feed(helper.pair(0.5, 0.7), seconds: 7)
        expectTrue(engine.alertVisible); expectEqual(engine.reminderSource, .gaze)
        feed(nil, seconds: 0.3); expectTrue(engine.alertVisible)
        feed(helper.pair(0.5, 0.7), seconds: 0.5); expectTrue(engine.alertVisible)
    }

    func testLostEyesClearGazeAlertAndHeadDetectionStillWorks() {
        prepare(); feed(helper.pair(0.5, 0.7), seconds: 12)
        expectTrue(engine.alertVisible)
        feed(nil, seconds: 1.2); expectFalse(engine.alertVisible)
        expectEqual(engine.gaze.awayDuration, 0, accuracy: 0.001)
        feed(nil, seconds: 10, yaw: 55)
        expectTrue(engine.alertVisible); expectEqual(engine.reminderSource, .head)
        feed(nil, seconds: 3); expectFalse(engine.alertVisible)
    }

    func testNoEyesAtStartupDoesNotLearnALaterDownwardStare() {
        feed(nil, seconds: 6.5)
        expectFalse(engine.gaze.calibrated)
        feed(helper.pair(0.5, 0.7), seconds: 20)
        expectFalse(engine.gaze.calibrated); expectFalse(engine.alertVisible)
        engine.reset(); prepare()
        feed(helper.pair(0.5, 0.7), seconds: 12)
        expectTrue(engine.alertVisible)
    }

    func testNoisyCalibrationFallsBackToHeadOnly() {
        for i in 0..<70 { feed(helper.pair(0.5, i % 2 == 0 ? 0.35 : 0.65), seconds: 0.1) }
        expectFalse(engine.gaze.calibrated)
        feed(helper.pair(0.5, 0.8), seconds: 12); expectFalse(engine.alertVisible)
        feed(nil, seconds: 10, pitch: 45); expectTrue(engine.alertVisible)
    }

    func testFrequentDropoutsCannotAccumulateReliableGazeEvidence() {
        prepare()
        for _ in 0..<70 {
            feed(helper.pair(0.5, 0.7), seconds: 0.3)
            feed(nil, seconds: 0.4)
        }
        expectFalse(engine.alertVisible)
        feed(nil, seconds: 1); expectEqual(engine.gaze.awayDuration, 0, accuracy: 0.001)
    }

    func testReturnNeedsEyesAsWellAsHeadAndHonorsCooldown() {
        prepare(); feed(helper.pair(0.5, 0.7), seconds: 12)
        expectTrue(engine.alertVisible)
        feed(helper.pair(0.5, 0.7), seconds: 4); expectTrue(engine.alertVisible)
        feed(helper.pair(), seconds: 3); expectFalse(engine.alertVisible)
        feed(helper.pair(0.5, 0.7), seconds: 20); expectFalse(engine.alertVisible)
        feed(helper.pair(0.5, 0.7), seconds: 6); expectTrue(engine.alertVisible)
    }

    func testHeadAndGazeEvidenceCannotBorrowEachOthersDuration() {
        prepare()
        feed(helper.pair(), seconds: 5, yaw: 55)
        feed(helper.pair(0.5, 0.7), seconds: 6)
        expectFalse(engine.alertVisible)
        feed(helper.pair(0.5, 0.7), seconds: 6); expectTrue(engine.alertVisible)
    }

    func testSideGazeAndNoiseThreshold() {
        prepare(); feed(helper.pair(0.65, 0.5), seconds: 12)
        expectTrue(engine.alertVisible); expectEqual(engine.gaze.direction, .left)
        engine.reset(); prepare()
        feed(helper.pair(0.5, 0.54), seconds: 20); expectFalse(engine.alertVisible)
    }

    func testResetAndUnknownClearEyeContinuity() {
        prepare(); feed(helper.pair(0.5, 0.7), seconds: 9)
        time += 0.1; engine.update(.unavailable, at: time)
        feed(helper.pair(0.5, 0.7), seconds: 3); expectFalse(engine.alertVisible)
        engine.reset(); expectFalse(engine.gaze.calibrated)
        expectNil(engine.reminderSource)
    }

    func testBlinkDuringStartupDoesNotPreventAutomaticEyeBaseline() {
        feed(helper.pair(), seconds: 5.5)
        feed(nil, seconds: 0.3)
        feed(helper.pair(), seconds: 0.7)
        expectTrue(engine.gaze.calibrated)
        feed(helper.pair(0.5, 0.7), seconds: 12)
        expectTrue(engine.alertVisible)
    }
}
