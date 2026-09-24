import Foundation
import FocusCore

final class AttentionEngineTests {
    var engine: AttentionEngine!
    var time = 0.0
    func setUp() {
        var config = AttentionConfig(); config.smoothingAlpha = 1
        engine = AttentionEngine(config: config); time = 0
    }
    func feed(_ sample: FaceState, seconds: Double) {
        for _ in 0..<Int((seconds * 10).rounded()) {
            time += 0.1; engine.update(sample, at: time)
        }
    }
    func face(_ pitch: Double = 0, _ yaw: Double = 0) -> FaceState {
        FaceState(faceDetected: true, pitch: pitch, yaw: yaw, roll: 0)
    }
    func calibrate(_ pitch: Double = 0, _ yaw: Double = 0) {
        feed(face(pitch, yaw), seconds: 6.5)
        expectEqual(engine.state, .focused)
    }
    func testBaselineUsesNaturalPoseAndRequiresStableValidFrames() {
        feed(.unavailable, seconds: 2); expectNil(engine.baselinePitch)
        feed(face(15, -10), seconds: 1)
        feed(face(-15, 20), seconds: 1); expectNil(engine.baselinePitch)
        feed(face(-15, 20), seconds: 5)
        expectEqual(engine.baselinePitch!, -15, accuracy: 0.001)
        expectEqual(engine.baselineYaw!, 20, accuracy: 0.001)
        feed(face(-15, 20), seconds: 10); expectFalse(engine.alertVisible)
    }
    func testShortGlancesDoNotAccumulate() {
        calibrate()
        for _ in 0..<5 {
            feed(face(0, 45), seconds: 4)
            feed(face(), seconds: 0.5)
        }
        expectFalse(engine.alertVisible)
        expectEqual(engine.state, .focused)
    }
    func testTurnRequiresSevenSecondsAndStableReturnThenCooldown() {
        calibrate()
        feed(face(0, 45), seconds: 6.9); expectFalse(engine.alertVisible)
        feed(face(0, 45), seconds: 0.3); expectTrue(engine.alertVisible)
        expectEqual(engine.state, .distracted)
        feed(face(), seconds: 1); expectEqual(engine.state, .returning); expectTrue(engine.alertVisible)
        feed(face(0, 45), seconds: 0.2)
        feed(face(), seconds: 1); expectTrue(engine.alertVisible)
        feed(face(), seconds: 0.7); expectFalse(engine.alertVisible)
        feed(face(0, 45), seconds: 24); expectFalse(engine.alertVisible)
        feed(face(0, 45), seconds: 1.2); expectTrue(engine.alertVisible)
    }
    func testPitchAndRelativeAngles() {
        calibrate(15, 10)
        feed(face(30, 30), seconds: 10); expectFalse(engine.alertVisible)
        feed(face(45, 10), seconds: 7.2); expectTrue(engine.alertVisible)
    }
    func testMissingFaceAwayAndRecovery() {
        calibrate()
        feed(FaceState(faceDetected: false), seconds: 2.9); expectFalse(engine.alertVisible)
        feed(FaceState(faceDetected: false), seconds: 0.3); expectEqual(engine.state, .suspected)
        feed(FaceState(faceDetected: false), seconds: 6); expectEqual(engine.state, .away); expectTrue(engine.alertVisible)
        feed(face(), seconds: 1.7); expectFalse(engine.alertVisible)
    }
    func testInvalidAnglesAndInferenceFailureNeverCountAsAway() {
        calibrate()
        feed(FaceState(faceDetected: true, pitch: nil, yaw: 55), seconds: 15)
        expectEqual(engine.state, .unknown); expectFalse(engine.alertVisible)
        feed(.unavailable, seconds: 15); expectFalse(engine.alertVisible)
        feed(face(.nan, 50), seconds: 10); expectFalse(engine.alertVisible)
    }
    func testDataGapResetsEvidenceAndDismissesStaleAlert() {
        calibrate(); feed(face(0, 45), seconds: 6)
        time += 5; engine.update(face(0, 45), at: time)
        expectFalse(engine.alertVisible)
        feed(face(0, 45), seconds: 7.2); expectTrue(engine.alertVisible)
        time += 5; engine.update(face(), at: time)
        expectFalse(engine.alertVisible)
    }
    func testUnknownResetsContinuityAndResetRemovesBaseline() {
        calibrate(); feed(face(0, 45), seconds: 6)
        feed(.unavailable, seconds: 0.1)
        feed(face(0, 45), seconds: 2); expectFalse(engine.alertVisible)
        engine.reset()
        expectNil(engine.baselinePitch); expectFalse(engine.alertVisible)
        expectEqual(engine.state, .calibrating)
    }
    func testReturnHasHysteresisAndRollAloneDoesNotAlert() {
        calibrate()
        feed(FaceState(faceDetected: true, pitch: 0, yaw: 0, roll: 70), seconds: 10)
        expectFalse(engine.alertVisible)
        feed(face(0, 45), seconds: 7.2)
        feed(face(0, 26), seconds: 3); expectTrue(engine.alertVisible)
        feed(face(0, 10), seconds: 1.7); expectFalse(engine.alertVisible)
    }
    func testEMARejectsSingleFrameSpike() {
        engine = AttentionEngine(); calibrate()
        feed(face(0, 70), seconds: 0.1)
        feed(face(), seconds: 1); expectEqual(engine.state, .focused); expectFalse(engine.alertVisible)
    }
    func testMissingFaceCannotCalibrateAndOldSamplesAreIgnored() {
        feed(FaceState(faceDetected: false), seconds: 20)
        expectNil(engine.baselinePitch); expectFalse(engine.alertVisible)
        calibrate()
        engine.update(face(0, 80), at: time - 5)
        expectEqual(engine.state, .focused)
    }

    func testStartupGlanceIsNotImmediatelyAcceptedAsBaseline() {
        feed(face(31, 6), seconds: 2)
        expectNil(engine.baselinePitch); expectFalse(engine.alertVisible)
        feed(face(12, 6), seconds: 4.5)
        expectEqual(engine.state, .focused)
        expectEqual(engine.baselinePitch!, 12, accuracy: 0.001)
        feed(face(12, 6), seconds: 12); expectFalse(engine.alertVisible)
    }

    func testStartupMovementAndInvalidFramesDelayReadiness() {
        for i in 0..<10 { feed(face(i % 2 == 0 ? 0 : 20), seconds: 1) }
        expectNil(engine.baselinePitch)
        feed(.unavailable, seconds: 0.1)
        feed(face(10, 5), seconds: 2); expectNil(engine.baselinePitch)
        feed(face(10, 5), seconds: 4.5)
        expectEqual(engine.baselinePitch!, 10, accuracy: 0.001)
    }

    func testSmallStablePoseChangesAdaptButBriefGlancesDoNot() {
        calibrate(12, 6)
        feed(face(16, 9), seconds: 5)
        expectEqual(engine.baselinePitch!, 12, accuracy: 0.001)
        feed(face(16, 9), seconds: 35)
        expectTrue(engine.baselinePitch! > 14)
        expectTrue(engine.baselinePitch! <= 16)
        expectTrue(engine.baselineYaw! > 7)
        expectFalse(engine.alertVisible)
    }

    func testGradualDriftCannotLearnASustainedHeadTurn() {
        calibrate()
        for angle in stride(from: 3.0, through: 36.0, by: 3.0) {
            feed(face(0, angle), seconds: 40)
        }
        expectTrue(engine.baselineYaw! <= 4.0001)
        expectTrue(engine.alertVisible)
        let baseline = engine.baselineYaw!
        feed(face(0, 50), seconds: 30)
        expectEqual(engine.baselineYaw!, baseline, accuracy: 0.001)
        feed(face(), seconds: 1.7); expectFalse(engine.alertVisible)
    }

    func testKeyboardSizedPitchChangeAlertsWithoutBecomingBaseline() {
        engine = AttentionEngine() // Exercise the shipped EMA as well as the threshold.
        calibrate(12.3, 9.3)
        feed(face(30.9, 6.2), seconds: 3); expectFalse(engine.alertVisible)
        feed(face(30.9, 6.2), seconds: 6.2); expectTrue(engine.alertVisible)
        expectEqual(engine.baselinePitch!, 12.3, accuracy: 0.001)
        feed(face(12.3, 9.3), seconds: 2.5); expectFalse(engine.alertVisible)
    }

    func testInvalidDataBreaksAdaptationAndResetDiscardsLearnedPose() {
        calibrate()
        feed(face(4, 4), seconds: 9)
        feed(.unavailable, seconds: 0.1)
        feed(face(4, 4), seconds: 5)
        expectEqual(engine.baselinePitch!, 0, accuracy: 0.001)
        feed(face(4, 4), seconds: 30)
        expectTrue(engine.baselinePitch! > 0)
        engine.reset()
        expectNil(engine.baselinePitch)
        calibrate(25, -10)
        expectEqual(engine.baselinePitch!, 25, accuracy: 0.001)
        expectEqual(engine.baselineYaw!, -10, accuracy: 0.001)
    }

    func testDiagnosticExplainsSmallRelativeChangesWithoutChangingState() {
        calibrate(12.3, 9.3)
        let sample = face(13.3, 16.2)
        feed(sample, seconds: 12)
        let baseline = engine.baselinePitch!
        let text = engine.diagnosticText(for: sample)
        expectTrue(text.contains("头部偏离未超过阈值"))
        expectTrue(text.contains("眼部基准不足，仅用头部判断"))
        expectTrue(text.contains("/ >18.0°"))
        expectFalse(engine.alertVisible)
        expectEqual(engine.baselinePitch!, baseline, accuracy: 0.001)
        feed(face(50, 9.3), seconds: 3)
        expectTrue(engine.diagnosticText(for: face(50, 9.3)).contains("等待持续满"))
        feed(face(50, 9.3), seconds: 5)
        expectTrue(engine.diagnosticText(for: face(50, 9.3)).contains("已触发提醒"))
        feed(face(12.3, 9.3), seconds: 2)
        expectTrue(engine.diagnosticText(for: face(12.3, 9.3)).contains("提醒冷却中"))
    }

    func testDiagnosticPreservesUnknownReasonAndClearsOldEvidence() {
        calibrate(); feed(face(0, 50), seconds: 4)
        let ambiguous = FaceState(faceDetected: true, valid: false, issue: .multipleFaces, faceCount: 2)
        engine.update(ambiguous, at: time + 0.1)
        let text = engine.diagnosticText(for: ambiguous)
        expectTrue(text.contains("检测到多张脸"))
        expectTrue(text.contains("连续偏离    0.0"))
        expectTrue(text.contains("俯仰 —° / >"))
        expectFalse(engine.alertVisible)
        engine.reset()
        expectTrue(engine.diagnosticText(for: face()).contains("尚未开始判断偏离"))
    }
}

final class FocusScheduleTests {
    let phases = [FocusPhase(kind: "focus", seconds: 900), FocusPhase(kind: "break", seconds: 300), FocusPhase(kind: "focus", seconds: 900)]
    func testNativeClockStopsAtBreakAndEndEvenWithoutWebTicks() {
        let schedule = FocusSchedule(running: true, startedAt: 1000, elapsed: 0, phases: phases, monitoring: true)
        expectTrue(schedule.shouldMonitor(at: 1899))
        expectFalse(schedule.shouldMonitor(at: 1900))
        expectTrue(schedule.shouldMonitor(at: 2200))
        expectFalse(schedule.shouldMonitor(at: 3100))
    }
    func testPauseDisabledCameraAndResumeFromElapsed() {
        expectFalse(FocusSchedule(running: false, startedAt: nil, elapsed: 400, phases: phases, monitoring: true).shouldMonitor(at: 1000))
        expectFalse(FocusSchedule(running: true, startedAt: 1000, elapsed: 0, phases: phases, monitoring: false).shouldMonitor(at: 1100))
        let resumed = FocusSchedule(running: true, startedAt: 1000, elapsed: 890, phases: phases, monitoring: true)
        expectTrue(resumed.shouldMonitor(at: 1009)); expectFalse(resumed.shouldMonitor(at: 1010))
    }
    func testInvalidBridgePayloadNeverStartsCamera() {
        expectFalse(FocusSchedule(running: true, startedAt: nil, elapsed: 0, phases: phases, monitoring: true).isValid)
        expectFalse(FocusSchedule(running: true, startedAt: 0, elapsed: -1, phases: phases, monitoring: true).isValid)
        expectFalse(FocusSchedule(running: true, startedAt: 0, elapsed: 0, phases: [FocusPhase(kind: "focus", seconds: .infinity)], monitoring: true).isValid)
    }
}
