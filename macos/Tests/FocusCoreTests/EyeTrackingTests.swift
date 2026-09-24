import Foundation
import FocusCore

final class EyeTrackingTests {
    let contour = [EyePoint(x: 0, y: 0), EyePoint(x: 10, y: 6), EyePoint(x: 30, y: 6), EyePoint(x: 40, y: 0), EyePoint(x: 30, y: -6), EyePoint(x: 10, y: -6)]
    func eye(_ x: Double = 0.5, _ y: Double = 0.5) -> EyeMeasurement {
        EyeGeometry.measure(contour: contour, pupil: EyePoint(x: x * 40, y: 6 - y * 12))!
    }
    func pair(_ x: Double = 0.5, _ y: Double = 0.5) -> EyePair { EyePair(left: eye(x, y), right: eye(x, y)) }
    func testGeometryUsesEyeLocalCoordinatesAndDownIsPositive() {
        let result = eye(0.6, 0.8)
        expectEqual(result.pupil.x, 0.6, accuracy: 0.001)
        expectEqual(result.pupil.y, 0.8, accuracy: 0.001)
        expectEqual(result.openness, 0.3, accuracy: 0.001)
    }
    func testGeometryIsInvariantToTranslationScaleAndRoll() {
        func transform(_ p: EyePoint) -> EyePoint {
            EyePoint(x: 2 * (p.x * cos(0.3) - p.y * sin(0.3)) + 140,
                     y: 2 * (p.x * sin(0.3) + p.y * cos(0.3)) + 90)
        }
        let measured = EyeGeometry.measure(contour: contour.map(transform), pupil: transform(EyePoint(x: 20, y: -3)))!
        expectEqual(measured.pupil.x, 0.5, accuracy: 0.001)
        expectEqual(measured.pupil.y, 0.75, accuracy: 0.001)
    }
    func testClosedTinyMissingAndInvalidEyesAreUnavailable() {
        expectNil(EyeGeometry.measure(contour: contour, pupil: nil))
        expectNil(EyeGeometry.measure(contour: contour.map { EyePoint(x: $0.x, y: $0.y * 0.1) }, pupil: EyePoint(x: 20, y: 0)))
        expectNil(EyeGeometry.measure(contour: contour.map { EyePoint(x: $0.x * 0.1, y: $0.y * 0.1) }, pupil: EyePoint(x: 2, y: 0)))
        expectNil(EyeGeometry.measure(contour: contour, pupil: EyePoint(x: .nan, y: 0)))
        expectNil(EyeGeometry.measure(contour: contour, pupil: EyePoint(x: 20, y: -50)))
    }
    func testBothEyesMustAgree() {
        expectNil(EyePair(left: eye(), right: nil).center)
        expectNil(EyePair(left: eye(0.1, 0.5), right: eye(0.9, 0.5)).center)
        expectNil(EyePair(left: eye(0.5, 0.2), right: eye(0.5, 0.8)).center)
    }
    func testGazeNeedsCalibrationAndStableDirection() {
        let engine = GazeEstimator()
        expectEqual(engine.update(pair(), at: 0), .uncalibrated)
        engine.calibrate(GazeReference(samples: Array(repeating: EyePoint(x: 0.5, y: 0.5), count: 12))!)
        engine.update(pair(0.5, 0.8), at: 0.1)
        expectEqual(engine.direction, .center)
        for i in 2...10 { engine.update(pair(0.5, 0.8), at: Double(i) / 10) }
        expectEqual(engine.direction, .down)
        engine.update(nil, at: 1.1)
        expectEqual(engine.direction, .unavailable); expectNil(engine.delta)
        for i in 12...24 { engine.update(pair(), at: Double(i) / 10) }
        expectEqual(engine.direction, .center)
    }
    func testGazeGapAndBlinkCannotRetainAnOldDirection() {
        let engine = GazeEstimator()
        engine.calibrate(GazeReference(samples: Array(repeating: EyePoint(x: 0.5, y: 0.5), count: 10))!)
        for i in 0...10 { engine.update(pair(0.8, 0.5), at: Double(i) / 10) }
        expectEqual(engine.direction, .left)
        engine.update(pair(), at: 4)
        expectEqual(engine.direction, .unavailable)
        engine.update(EyePair(left: nil, right: nil), at: 4.1)
        expectEqual(engine.direction, .unavailable)
    }
    func testReferenceRequiresEnoughSamplesAndDifferenceAboveNoise() {
        expectNil(GazeReference(samples: [EyePoint(x: 0.5, y: 0.5)]))
        let center = GazeReference(samples: Array(repeating: EyePoint(x: 0.5, y: 0.5), count: 10))!
        let keyboard = GazeReference(samples: Array(repeating: EyePoint(x: 0.5, y: 0.7), count: 10))!
        expectTrue(keyboard.separatesVertically(from: center))
        let close = GazeReference(samples: Array(repeating: EyePoint(x: 0.5, y: 0.54), count: 10))!
        expectFalse(close.separatesVertically(from: center))
        let noise = GazeReference(samples: (0..<12).map { EyePoint(x: 0.5, y: $0 % 2 == 0 ? 0.3 : 0.8) })!
        expectFalse(noise.stable)
        expectFalse(noise.separatesVertically(from: center))
    }
    func testEyeEvidenceTriggersProductionReminderWithoutHeadMovement() {
        let engine = AttentionEngine()
        for i in 0...200 {
            engine.update(FaceState(faceDetected: true, pitch: 13.7, yaw: 7.9, eyes: pair(0.5, i > 65 ? 0.7 : 0.5)), at: Double(i) / 10)
        }
        expectTrue(engine.alertVisible); expectEqual(engine.reminderSource, .gaze)
        expectEqual(engine.gaze.direction, .down)
        for i in 201...235 {
            engine.update(FaceState(faceDetected: true, pitch: 13.7, yaw: 7.9, eyes: pair()), at: Double(i) / 10)
        }
        expectFalse(engine.alertVisible); expectEqual(engine.state, .focused)
    }
}
