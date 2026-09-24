import Foundation

var failures = 0
var checks = 0
func fail(_ message: String, file: StaticString, line: UInt) {
    failures += 1; fputs("FAIL \(file):\(line): \(message)\n", stderr)
}
func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    if lhs != rhs { fail("\(lhs) != \(rhs)", file: file, line: line) }
}
func expectEqual(_ lhs: Double, _ rhs: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    if abs(lhs - rhs) > accuracy { fail("\(lhs) != \(rhs)", file: file, line: line) }
}
func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value { fail("Expected true", file: file, line: line) }
}
func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if value { fail("Expected false", file: file, line: line) }
}
func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value != nil { fail("Expected nil", file: file, line: line) }
}
func run(_ name: String, _ block: () -> Void) {
    let before = failures; block(); checks += 1
    print("\(failures == before ? "PASS" : "FAIL") \(name)")
}
run("testBaselineUsesNaturalPoseAndRequiresStableValidFrames") { let suite = AttentionEngineTests(); suite.setUp(); suite.testBaselineUsesNaturalPoseAndRequiresStableValidFrames() }
run("testShortGlancesDoNotAccumulate") { let suite = AttentionEngineTests(); suite.setUp(); suite.testShortGlancesDoNotAccumulate() }
run("testTurnRequiresSevenSecondsAndStableReturnThenCooldown") { let suite = AttentionEngineTests(); suite.setUp(); suite.testTurnRequiresSevenSecondsAndStableReturnThenCooldown() }
run("testPitchAndRelativeAngles") { let suite = AttentionEngineTests(); suite.setUp(); suite.testPitchAndRelativeAngles() }
run("testMissingFaceAwayAndRecovery") { let suite = AttentionEngineTests(); suite.setUp(); suite.testMissingFaceAwayAndRecovery() }
run("testInvalidAnglesAndInferenceFailureNeverCountAsAway") { let suite = AttentionEngineTests(); suite.setUp(); suite.testInvalidAnglesAndInferenceFailureNeverCountAsAway() }
run("testDataGapResetsEvidenceAndDismissesStaleAlert") { let suite = AttentionEngineTests(); suite.setUp(); suite.testDataGapResetsEvidenceAndDismissesStaleAlert() }
run("testUnknownResetsContinuityAndResetRemovesBaseline") { let suite = AttentionEngineTests(); suite.setUp(); suite.testUnknownResetsContinuityAndResetRemovesBaseline() }
run("testReturnHasHysteresisAndRollAloneDoesNotAlert") { let suite = AttentionEngineTests(); suite.setUp(); suite.testReturnHasHysteresisAndRollAloneDoesNotAlert() }
run("testEMARejectsSingleFrameSpike") { let suite = AttentionEngineTests(); suite.setUp(); suite.testEMARejectsSingleFrameSpike() }
run("testMissingFaceCannotCalibrateAndOldSamplesAreIgnored") { let suite = AttentionEngineTests(); suite.setUp(); suite.testMissingFaceCannotCalibrateAndOldSamplesAreIgnored() }
run("testStartupGlanceIsNotImmediatelyAcceptedAsBaseline") { let suite = AttentionEngineTests(); suite.setUp(); suite.testStartupGlanceIsNotImmediatelyAcceptedAsBaseline() }
run("testStartupMovementAndInvalidFramesDelayReadiness") { let suite = AttentionEngineTests(); suite.setUp(); suite.testStartupMovementAndInvalidFramesDelayReadiness() }
run("testSmallStablePoseChangesAdaptButBriefGlancesDoNot") { let suite = AttentionEngineTests(); suite.setUp(); suite.testSmallStablePoseChangesAdaptButBriefGlancesDoNot() }
run("testGradualDriftCannotLearnASustainedHeadTurn") { let suite = AttentionEngineTests(); suite.setUp(); suite.testGradualDriftCannotLearnASustainedHeadTurn() }
run("testKeyboardSizedPitchChangeAlertsWithoutBecomingBaseline") { let suite = AttentionEngineTests(); suite.setUp(); suite.testKeyboardSizedPitchChangeAlertsWithoutBecomingBaseline() }
run("testInvalidDataBreaksAdaptationAndResetDiscardsLearnedPose") { let suite = AttentionEngineTests(); suite.setUp(); suite.testInvalidDataBreaksAdaptationAndResetDiscardsLearnedPose() }
run("testDiagnosticExplainsSmallRelativeChangesWithoutChangingState") { let suite = AttentionEngineTests(); suite.setUp(); suite.testDiagnosticExplainsSmallRelativeChangesWithoutChangingState() }
run("testDiagnosticPreservesUnknownReasonAndClearsOldEvidence") { let suite = AttentionEngineTests(); suite.setUp(); suite.testDiagnosticPreservesUnknownReasonAndClearsOldEvidence() }
run("testNativeClockStopsAtBreakAndEndEvenWithoutWebTicks") { let suite = FocusScheduleTests(); suite.testNativeClockStopsAtBreakAndEndEvenWithoutWebTicks() }
run("testPauseDisabledCameraAndResumeFromElapsed") { let suite = FocusScheduleTests(); suite.testPauseDisabledCameraAndResumeFromElapsed() }
run("testInvalidBridgePayloadNeverStartsCamera") { let suite = FocusScheduleTests(); suite.testInvalidBridgePayloadNeverStartsCamera() }
run("testGeometryUsesEyeLocalCoordinatesAndDownIsPositive") { EyeTrackingTests().testGeometryUsesEyeLocalCoordinatesAndDownIsPositive() }
run("testGeometryIsInvariantToTranslationScaleAndRoll") { EyeTrackingTests().testGeometryIsInvariantToTranslationScaleAndRoll() }
run("testClosedTinyMissingAndInvalidEyesAreUnavailable") { EyeTrackingTests().testClosedTinyMissingAndInvalidEyesAreUnavailable() }
run("testBothEyesMustAgree") { EyeTrackingTests().testBothEyesMustAgree() }
run("testGazeNeedsCalibrationAndStableDirection") { EyeTrackingTests().testGazeNeedsCalibrationAndStableDirection() }
run("testGazeGapAndBlinkCannotRetainAnOldDirection") { EyeTrackingTests().testGazeGapAndBlinkCannotRetainAnOldDirection() }
run("testReferenceRequiresEnoughSamplesAndDifferenceAboveNoise") { EyeTrackingTests().testReferenceRequiresEnoughSamplesAndDifferenceAboveNoise() }
run("testEyeEvidenceTriggersProductionReminderWithoutHeadMovement") { EyeTrackingTests().testEyeEvidenceTriggersProductionReminderWithoutHeadMovement() }
run("testShortGlancesAndOneEyeDisagreementNeverAlert") { AttentionGazeTests().testShortGlancesAndOneEyeDisagreementNeverAlert() }
run("testBlinkPausesEvidenceButDoesNotPreventSustainedGazeAlert") { AttentionGazeTests().testBlinkPausesEvidenceButDoesNotPreventSustainedGazeAlert() }
run("testLostEyesClearGazeAlertAndHeadDetectionStillWorks") { AttentionGazeTests().testLostEyesClearGazeAlertAndHeadDetectionStillWorks() }
run("testNoEyesAtStartupDoesNotLearnALaterDownwardStare") { AttentionGazeTests().testNoEyesAtStartupDoesNotLearnALaterDownwardStare() }
run("testNoisyCalibrationFallsBackToHeadOnly") { AttentionGazeTests().testNoisyCalibrationFallsBackToHeadOnly() }
run("testFrequentDropoutsCannotAccumulateReliableGazeEvidence") { AttentionGazeTests().testFrequentDropoutsCannotAccumulateReliableGazeEvidence() }
run("testReturnNeedsEyesAsWellAsHeadAndHonorsCooldown") { AttentionGazeTests().testReturnNeedsEyesAsWellAsHeadAndHonorsCooldown() }
run("testHeadAndGazeEvidenceCannotBorrowEachOthersDuration") { AttentionGazeTests().testHeadAndGazeEvidenceCannotBorrowEachOthersDuration() }
run("testSideGazeAndNoiseThreshold") { AttentionGazeTests().testSideGazeAndNoiseThreshold() }
run("testResetAndUnknownClearEyeContinuity") { AttentionGazeTests().testResetAndUnknownClearEyeContinuity() }
run("testBlinkDuringStartupDoesNotPreventAutomaticEyeBaseline") { AttentionGazeTests().testBlinkDuringStartupDoesNotPreventAutomaticEyeBaseline() }
run("testSustainedOpennessFindsVerticalMotionWithStationaryNormalizedPupils") { EyelidGazeTests().testSustainedOpennessFindsVerticalMotionWithStationaryNormalizedPupils() }
run("testBriefNarrowingBlinksAndMissingFramesDoNotJoin") { EyelidGazeTests().testBriefNarrowingBlinksAndMissingFramesDoNotJoin() }
run("testOneEyeAndConflictingPupilsCannotActivateEyelidFallback") { EyelidGazeTests().testOneEyeAndConflictingPupilsCannotActivateEyelidFallback() }
run("testHorizontalPupilsKeepPriorityAndProductionIsUnchanged") { EyelidGazeTests().testHorizontalPupilsKeepPriorityAndProductionIsUnchanged() }
run("testUnstableLidBaselineDoesNotDisablePupilTrackingAndResetClearsIt") { EyelidGazeTests().testUnstableLidBaselineDoesNotDisablePupilTrackingAndResetClearsIt() }
run("testHeadPoseGateAlsoStopsEyelidCue") { EyelidGazeTests().testHeadPoseGateAlsoStopsEyelidCue() }
print("\(checks) scenarios, \(failures) failures")
exit(failures == 0 ? 0 : 1)
