@preconcurrency import AVFoundation
import CoreImage
@preconcurrency import CoreVideo
import Foundation
import UIKit
import Vision

@MainActor
final class LocalCameraMonitoringService: NSObject, CameraMonitoringService {
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "BabyMont.camera.session", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "BabyMont.camera.frames", qos: .userInitiated)
    private let imageContext = CIContext()
    private var isConfigured = false
    private var frameCounter = 0
    private var lastVisionAnalysis = Date.distantPast

    private(set) var signal = CameraSignal()
    private(set) var latestFrame: VisionFrame?

    var session: AVCaptureSession? {
        captureSession
    }

    func start() async {
        signal.state = .requestingPermission

        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { continuation.resume(returning: $0) }
        }

        guard granted else {
            signal.state = .denied("Camera permission is required for local video monitoring.")
            return
        }

        do {
            try configureIfNeeded()
            signal.state = .active
            signal.frameRate = 30
            if !captureSession.isRunning {
                sessionQueue.async { [captureSession] in
                    captureSession.startRunning()
                }
            }
        } catch {
            signal.state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        if captureSession.isRunning {
            sessionQueue.async { [captureSession] in
                captureSession.stopRunning()
            }
        }
        latestFrame = nil
        signal = CameraSignal(state: .idle)
    }

    func captureSnapshot() -> UIImage? {
        guard let pixelBuffer = latestFrame?.pixelBuffer else { return nil }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .right)
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium
        defer { captureSession.commitConfiguration() }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.noCamera
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard captureSession.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }

        captureSession.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        guard captureSession.canAddOutput(videoOutput) else {
            throw CameraError.cannotAddOutput
        }

        captureSession.addOutput(videoOutput)
        videoOutput.connection(with: .video)?.videoRotationAngle = 90
        isConfigured = true
    }

    private func updateFrame(_ pixelBuffer: CVPixelBuffer, timestamp: Date) {
        frameCounter += 1
        latestFrame = VisionFrame(timestamp: timestamp, pixelBuffer: pixelBuffer)
        signal.capturedFrameCount = frameCounter
        signal.state = .active

        guard timestamp.timeIntervalSince(lastVisionAnalysis) >= 0.75 else { return }
        lastVisionAnalysis = timestamp
        analyzeOccupancy(in: pixelBuffer, timestamp: timestamp)
    }

    private func analyzeOccupancy(in pixelBuffer: CVPixelBuffer, timestamp: Date) {
        let faceRequest = VNDetectFaceRectanglesRequest()
        let personRequest = VNDetectHumanRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])

        do {
            try handler.perform([faceRequest, personRequest])
            let faceConfidence = faceRequest.results?.map(\.confidence).max().map(Double.init) ?? 0
            let personConfidence = personRequest.results?.map(\.confidence).max().map(Double.init) ?? 0
            let occupancy = max(faceConfidence, personConfidence)

            signal.faceConfidence = faceConfidence
            signal.personConfidence = personConfidence
            signal.occupancyConfidence = occupancy
            signal.isLowLight = false
            signal.state = .active
        } catch {
            signal.state = .failed(error.localizedDescription)
        }
    }
}

extension LocalCameraMonitoringService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let date = timestamp.isFinite ? Date(timeIntervalSince1970: timestamp) : .now

        Task { @MainActor in
            self.updateFrame(pixelBuffer, timestamp: date)
        }
    }
}

private enum CameraError: LocalizedError {
    case noCamera
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noCamera: "No local camera was found on this device."
        case .cannotAddInput: "The camera input could not be attached."
        case .cannotAddOutput: "The camera frame output could not be attached."
        }
    }
}
