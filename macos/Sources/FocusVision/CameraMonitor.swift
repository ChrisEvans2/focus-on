import AVFoundation
import Vision
import ImageIO
import FocusCore

/// Raw Vision locations in image-normalized, bottom-left coordinates. Kept only
/// for the optional debug viewer; these are not the normalized EyeGeometry result.
public struct VisionOverlay {
    public var faces: [CGRect] = []
    public var leftEye: [CGPoint] = []
    public var rightEye: [CGPoint] = []
    public var leftPupil: [CGPoint] = []
    public var rightPupil: [CGPoint] = []
    public init() {}
}

public final class VisionAnalyzer {
    public private(set) var overlay = VisionOverlay()
    private let includeEyes: Bool
    private let landmarks = VNDetectFaceLandmarksRequest()
    public init(includeEyes: Bool = false) { self.includeEyes = includeEyes }
    private let request: VNDetectFaceRectanglesRequest = {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        return request
    }()

    public func analyze(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> FaceState {
        overlay = VisionOverlay()
        guard isUsablyLit(buffer) else { return FaceState(faceDetected: false, valid: false, issue: .lowLight) }
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation).perform([request])
            let faces = request.results ?? []
            overlay.faces = faces.map(\.boundingBox)
            guard !faces.isEmpty else { return FaceState(faceDetected: false, faceCount: 0) }
            // Do not silently change the tracked user when someone else enters the frame.
            guard faces.count == 1 else {
                return FaceState(faceDetected: true, valid: false, issue: .multipleFaces, faceCount: faces.count)
            }
            guard let face = faces.first, face.confidence >= 0.6 else {
                return FaceState(faceDetected: true, valid: false, issue: .lowConfidence, faceCount: faces.count,
                                 confidence: faces.first.map { Double($0.confidence) })
            }
            var eyes: EyePair?
            if includeEyes {
                landmarks.inputFaceObservations = [face]
                do {
                    try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation).perform([landmarks])
                    if let observation = landmarks.results?.first, let points = observation.landmarks {
                        let box = observation.boundingBox
                        func imagePoints(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
                            region?.normalizedPoints.map {
                                CGPoint(x: box.minX + CGFloat($0.x) * box.width, y: box.minY + CGFloat($0.y) * box.height)
                            } ?? []
                        }
                        overlay.leftEye = imagePoints(points.leftEye); overlay.rightEye = imagePoints(points.rightEye)
                        overlay.leftPupil = imagePoints(points.leftPupil); overlay.rightPupil = imagePoints(points.rightPupil)
                        if points.confidence >= 0.5 {
                        let width = Double(CVPixelBufferGetWidth(buffer)) * observation.boundingBox.width
                        let height = Double(CVPixelBufferGetHeight(buffer)) * observation.boundingBox.height
                        func eye(_ contour: VNFaceLandmarkRegion2D?, _ pupil: VNFaceLandmarkRegion2D?) -> EyeMeasurement? {
                            guard let contour, let pupil, pupil.pointCount == 1 else { return nil }
                            let outline = contour.normalizedPoints.map { EyePoint(x: Double($0.x) * width, y: Double($0.y) * height) }
                            let center = pupil.normalizedPoints[0]
                            return EyeGeometry.measure(contour: outline, pupil: EyePoint(x: Double(center.x) * width, y: Double(center.y) * height))
                        }
                        eyes = EyePair(left: eye(points.leftEye, points.leftPupil), right: eye(points.rightEye, points.rightPupil))
                        }
                    }
                } catch { eyes = nil }
            }
            return FaceState(faceDetected: true,
                pitch: face.pitch.map { $0.doubleValue * 180 / .pi },
                yaw: face.yaw.map { $0.doubleValue * 180 / .pi },
                roll: face.roll.map { $0.doubleValue * 180 / .pi }, eyes: eyes,
                issue: face.pitch == nil || face.yaw == nil ? .missingAngles : nil,
                faceCount: faces.count, confidence: Double(face.confidence))
        } catch { return FaceState(faceDetected: false, valid: false, issue: .inferenceFailed) }
    }
    private func isUsablyLit(_ buffer: CVPixelBuffer) -> Bool {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return false }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return false }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0 else { return false }
        var luminance = 0.0
        for y in 0..<10 {
            for x in 0..<10 {
                let offset = min(height - 1, (y * 2 + 1) * height / 20) * stride + min(width - 1, (x * 2 + 1) * width / 20) * 4
                luminance += 0.0722 * Double(bytes[offset]) + 0.7152 * Double(bytes[offset + 1]) + 0.2126 * Double(bytes[offset + 2])
            }
        }
        return luminance / 100 >= 18
    }
}

public protocol CameraCapturing: AnyObject {
    func start(onSample: @escaping (FaceState, Double) -> Void, onFailure: @escaping (String) -> Void)
    func stop()
    func stop(completion: @escaping () -> Void)
}

/// Session configuration, capture and analysis are serialized off the main thread.
public final class CameraMonitor: NSObject, CameraCapturing, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let queue = DispatchQueue(label: "focus.camera.analysis", qos: .utility)
    private let session = AVCaptureSession()
    private let analyzer: VisionAnalyzer
    private let includeEyes: Bool
    private let onDebugFrame: ((CVPixelBuffer, VisionOverlay, FaceState, Double) -> Void)?
    public init(includeEyes: Bool = false,
                onDebugFrame: ((CVPixelBuffer, VisionOverlay, FaceState, Double) -> Void)? = nil) {
        self.includeEyes = includeEyes
        self.onDebugFrame = onDebugFrame
        analyzer = VisionAnalyzer(includeEyes: includeEyes)
        super.init()
    }
    private var onSample: ((FaceState, Double) -> Void)?
    private var onFailure: ((String) -> Void)?
    private var lastAnalysis = -Double.infinity
    private var observers: [NSObjectProtocol] = []
    private var orientation: CGImagePropertyOrientation = .up

    public func start(onSample: @escaping (FaceState, Double) -> Void,
               onFailure: @escaping (String) -> Void) {
        queue.async { [self] in
            tearDown()
            self.onSample = onSample; self.onFailure = onFailure
            lastAnalysis = -.infinity
            guard let device = AVCaptureDevice.default(for: .video) else {
                onFailure("未找到摄像头，仍可继续计时"); return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.setSampleBufferDelegate(self, queue: queue)
                session.beginConfiguration()
                let preferred: AVCaptureSession.Preset = includeEyes ? .hd1280x720 : .vga640x480
                if session.canSetSessionPreset(preferred) { session.sessionPreset = preferred }
                else if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration(); onFailure("摄像头暂不可用，仍可继续计时"); return
                }
                session.addInput(input); session.addOutput(output)
                if let connection = output.connection(with: .video) {
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                    // Rotate the actual pixel buffers before Vision. External cameras report 0°
                    // when their physical orientation is unknown; normal upright mounting is assumed.
                    if #available(macOS 14.0, *) {
                        let rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
                        let angle = rotation.videoRotationAngleForHorizonLevelCapture
                        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
                    }
                }
                orientation = .up
                session.commitConfiguration()
                for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                        self?.queue.async { [weak self] in
                            guard let self else { return }
                            let callback = self.onFailure
                            self.tearDown()
                            callback?("摄像头被中断，请重试监测；计时继续")
                        }
                    })
                }
                session.startRunning()
                if !session.isRunning { tearDown(); onFailure("摄像头启动失败，请重试监测；计时继续") }
            } catch { tearDown(); onFailure("摄像头暂不可用，请检查连接与权限") }
        }
    }

    public func stop() { queue.async { [self] in tearDown() } }
    public func stop(completion: @escaping () -> Void) {
        queue.async { [self] in
            tearDown()
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func tearDown() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        onSample = nil; onFailure = nil
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.commitConfiguration()
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastAnalysis >= 1.0 / 7.5, let onSample else { return }
        lastAnalysis = now
        autoreleasepool {
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                onSample(.unavailable, now); return
            }
            let sample = analyzer.analyze(buffer, orientation: orientation)
            onSample(sample, now)
            onDebugFrame?(buffer, analyzer.overlay, sample, now)
        }
    }
}
