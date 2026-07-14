//
//  CameraModel.swift
//  CameraKit
//
//  Created by AnhPT on 02/07/2026.
//

import AVFoundation
import UIKit
import Observation

/// Errors surfaced by `CameraModel`.
public enum CameraError: Error, Sendable {
    case unauthorized
    case configurationFailed
    case captureFailed
}

/// An `@Observable` AVFoundation camera controller (iOS 17+), modeled on Apple's
/// AVCam sample: a dedicated session queue, permission handling, tap-to-focus,
/// pinch-to-zoom, torch, and modern rotation via `RotationCoordinator`.
///
/// Requires `NSCameraUsageDescription` in Info.plist.
@MainActor
@Observable
public final class CameraModel {
    public enum FlashMode: Sendable { case off, on, auto }

    // Observable state
    public private(set) var isConfigured = false
    public private(set) var isRunning = false
    public private(set) var position: AVCaptureDevice.Position = .back
    public private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    public private(set) var zoomFactor: CGFloat = 1
    public private(set) var minZoomFactor: CGFloat = 1
    public private(set) var maxZoomFactor: CGFloat = 1
    public private(set) var isTorchOn = false
    public private(set) var error: CameraError?
    public var flashMode: FlashMode = .auto

    /// `true` while the capture session is interrupted (incoming call, audio/video
    /// route change, app backgrounded, resources in use by another client…).
    public private(set) var isInterrupted = false
    /// Why the session is currently interrupted (`nil` when not interrupted).
    public private(set) var interruptionReason: AVCaptureSession.InterruptionReason?

    /// The session to feed into `CameraPreview`.
    ///
    /// `AVCaptureSession` is not `Sendable`. It is created here and thereafter
    /// mutated/read only inside `queue.async` blocks on the serial session
    /// `queue`, which serializes all access; `nonisolated(unsafe)` lets those
    /// off-main blocks reach it without hopping to the main actor.
    nonisolated(unsafe) public let session = AVCaptureSession()

    /// Not `Sendable`; configured and used only on the serial session `queue`.
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    // Internal AVFoundation plumbing, not observable UI state. Mutated only on
    // the serial session `queue`, so `nonisolated(unsafe)` is sound.
    @ObservationIgnored nonisolated(unsafe) private var videoInput: AVCaptureDeviceInput?
    @ObservationIgnored nonisolated(unsafe) private var captureDelegate: PhotoCaptureDelegate?
    @ObservationIgnored private let queue = DispatchQueue(label: "com.anvyx.camerakit.session")

    // Live video-frame streaming (for on-device Vision analysis, e.g. a scanner).
    @ObservationIgnored nonisolated(unsafe) private let videoDataOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored private let frameForwarder = FrameForwarder()
    @ObservationIgnored private let frameQueue = DispatchQueue(label: "com.anvyx.camerakit.frames")

    // Rotation (iOS 17 RotationCoordinator)
    @ObservationIgnored private weak var previewLayer: AVCaptureVideoPreviewLayer?
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private var interruptionTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var captureRotationAngle: CGFloat = 90

    public init() {
        observeInterruptions()
    }

    deinit {
        interruptionTasks.forEach { $0.cancel() }
    }

    // MARK: - Interruptions

    /// Track `AVCaptureSession` interruption / resume for this session so the UI
    /// can react (e.g. dim the preview during a call). Uses the notification
    /// AsyncSequence — no manual observer tokens, no polling.
    private func observeInterruptions() {
        interruptionTasks.forEach { $0.cancel() }
        let center = NotificationCenter.default
        interruptionTasks = [
            Task { @MainActor [weak self] in
                for await note in center.notifications(named: AVCaptureSession.wasInterruptedNotification) {
                    self?.beginInterruption(note)
                }
            },
            Task { @MainActor [weak self] in
                for await note in center.notifications(named: AVCaptureSession.interruptionEndedNotification) {
                    self?.endInterruption(note)
                }
            },
        ]
    }

    func beginInterruption(_ note: Notification) {
        guard (note.object as? AVCaptureSession) === session else { return }
        let raw = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
        interruptionReason = raw.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
        isInterrupted = true
    }

    func endInterruption(_ note: Notification) {
        guard (note.object as? AVCaptureSession) === session else { return }
        isInterrupted = false
        interruptionReason = nil
    }

    // MARK: - Authorization

    @discardableResult
    public func requestAccess() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        return granted
    }

    // MARK: - Lifecycle

    /// Request access (if needed) and build the session graph. Call once before `start()`.
    public func configure() async {
        if authorizationStatus == .notDetermined {
            _ = await requestAccess()
        }
        guard authorizationStatus == .authorized else {
            error = .unauthorized
            return
        }

        let position = self.position
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                session.beginConfiguration()
                session.sessionPreset = .photo
                if let device = Self.device(for: position),
                   let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input) {
                    session.addInput(input)
                    videoInput = input
                }
                if session.canAddOutput(photoOutput) {
                    photoOutput.maxPhotoQualityPrioritization = .quality
                    session.addOutput(photoOutput)
                }
                videoDataOutput.alwaysDiscardsLateVideoFrames = true
                videoDataOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                ]
                if session.canAddOutput(videoDataOutput) {
                    session.addOutput(videoDataOutput)
                }
                session.commitConfiguration()
                continuation.resume()
            }
        }

        if videoInput == nil {
            error = .configurationFailed
            return
        }
        updateZoomRange()
        isConfigured = true
    }

    // MARK: - Live video frames

    /// Stream live camera frames for on-device analysis (e.g. document/text
    /// detection). `handler` is called on a background queue for each frame —
    /// keep it fast and hop to the main actor only to publish results. Call
    /// ``stopVideoFrames()`` when done.
    public func startVideoFrames(_ handler: @escaping @Sendable (CMSampleBuffer) -> Void) {
        frameForwarder.onFrame = handler
        queue.async { [self] in
            videoDataOutput.setSampleBufferDelegate(frameForwarder, queue: frameQueue)
        }
    }

    /// Stop delivering live frames (see ``startVideoFrames(_:)``).
    public func stopVideoFrames() {
        frameForwarder.onFrame = nil
        queue.async { [self] in
            videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
        }
    }

    /// Live camera frames as an `AsyncStream`, keeping only the newest frame so
    /// analysis stays real-time (older frames are dropped rather than queued).
    /// Consume with `for await frame in camera.videoFrames()`; the stream stops
    /// delivering when the consuming task is cancelled.
    public func videoFrames() -> AsyncStream<CameraFrame> {
        AsyncStream(CameraFrame.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            frameForwarder.onFrame = { continuation.yield(CameraFrame(sampleBuffer: $0)) }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.stopVideoFrames() }
            }
            queue.async { [self] in
                videoDataOutput.setSampleBufferDelegate(frameForwarder, queue: frameQueue)
            }
        }
    }

    // MARK: - Hardware Camera Control (iPhone 16+)

    /// Add the system zoom and exposure-bias sliders driven by the hardware
    /// Camera Control button. No-op on devices/sessions without Camera Control
    /// support (`canAddControl` returns false). Call after `configure()`.
    public func enableHardwareCameraControls() {
        queue.async { [self] in
            guard let device = videoInput?.device else { return }
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            let controls: [AVCaptureControl] = [
                AVCaptureSystemZoomSlider(device: device),
                AVCaptureSystemExposureBiasSlider(device: device),
            ]
            for control in controls where session.canAddControl(control) {
                session.addControl(control)
            }
        }
    }

    /// Add a custom Camera Control built by `make` (e.g. an `AVCaptureSlider`).
    /// The control is constructed on the session queue. No-op if the session can't
    /// accept it (unsupported, or `maxControlsCount` reached).
    public func addCameraControl(_ make: @escaping @Sendable () -> AVCaptureControl) {
        queue.async { [self] in
            let control = make()
            guard session.canAddControl(control) else { return }
            session.beginConfiguration()
            session.addControl(control)
            session.commitConfiguration()
        }
    }

    // MARK: - Advanced capture (best-effort; no-ops when unsupported/no device)

    /// Enable **Cinematic Video** capture with a depth-of-field look (iOS 26).
    /// - Parameter simulatedAperture: smaller = shallower depth of field.
    @available(iOS 26, *)
    public func enableCinematicVideo(simulatedAperture: Float? = nil) {
        queue.async { [self] in
            guard let videoInput, videoInput.device.activeFormat.isCinematicVideoCaptureSupported else { return }
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            videoInput.isCinematicVideoCaptureEnabled = true
            if let simulatedAperture { videoInput.simulatedAperture = simulatedAperture }
        }
    }

    /// Enable **Apple ProRAW** capture on supported devices.
    public func setProRAWEnabled(_ enabled: Bool) {
        queue.async { [self] in
            guard photoOutput.isAppleProRAWSupported else { return }
            session.beginConfiguration()
            photoOutput.isAppleProRAWEnabled = enabled
            session.commitConfiguration()
        }
    }

    /// Enable **Constant Color** capture (consistent color under varied light, iOS 18).
    @available(iOS 18, *)
    public func setConstantColorEnabled(_ enabled: Bool) {
        queue.async { [self] in
            guard photoOutput.isConstantColorSupported else { return }
            session.beginConfiguration()
            photoOutput.isConstantColorEnabled = enabled
            session.commitConfiguration()
        }
    }

    /// Set the preferred video stabilization mode on the capture connection.
    public func setVideoStabilization(_ mode: AVCaptureVideoStabilizationMode) {
        queue.async { [self] in
            guard let connection = photoOutput.connection(with: .video),
                  connection.isVideoStabilizationSupported else { return }
            connection.preferredVideoStabilizationMode = mode
        }
    }

    public func start() {
        queue.async { [self] in
            guard !session.isRunning else { return }
            session.startRunning()
            Task { @MainActor in self.isRunning = true }
        }
    }

    public func stop() {
        queue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
            Task { @MainActor in self.isRunning = false }
        }
    }

    /// Wire the preview layer so rotation stays correct (call from `CameraPreview`).
    public func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        guard let device = videoInput?.device else { return }
        createRotationCoordinator(for: device, previewLayer: layer)
    }

    // MARK: - Capture

    public func capturePhoto() async -> UIImage? {
        guard isConfigured else { return nil }
        // `AVCapturePhotoSettings` is not `Sendable`; build it on the session
        // `queue` and hand it only Sendable values captured from the main actor.
        let flashMode = avFlashMode
        let angle = captureRotationAngle

        return await withCheckedContinuation { continuation in
            let delegate = PhotoCaptureDelegate { [weak self] image in
                if image == nil { Task { @MainActor in self?.error = .captureFailed } }
                continuation.resume(returning: image)
            }
            captureDelegate = delegate
            queue.async { [self] in
                let settings: AVCapturePhotoSettings = photoOutput.availablePhotoCodecTypes.contains(.hevc)
                    ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                    : AVCapturePhotoSettings()
                settings.flashMode = flashMode
                settings.photoQualityPrioritization = .quality
                if #available(iOS 18, *), photoOutput.isShutterSoundSuppressionSupported {
                    settings.isShutterSoundSuppressionEnabled = true
                }
                if let connection = photoOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    // MARK: - Focus stabilization (crisp document capture)

    /// Wait (up to `timeout`s) until focus & exposure stop adjusting, then lock
    /// them — so a capture isn't taken mid-adjustment. Call before ``capturePhoto()``
    /// and pair with ``restoreContinuousFocus()`` afterwards.
    public func lockFocusAndExposureWhenStable(timeout: TimeInterval = 1.5) async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let device = videoInput?.device else { continuation.resume(); return }
                let deadline = Date().addingTimeInterval(timeout)
                while device.isAdjustingFocus || device.isAdjustingExposure, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if (try? device.lockForConfiguration()) != nil {
                    if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                    if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
                    device.unlockForConfiguration()
                }
                continuation.resume()
            }
        }
    }

    /// Tune focus/exposure for close-range document scanning: continuous AF with
    /// the near-range restriction, smooth AF, and centered focus/exposure.
    public func configureForDocumentScanning() {
        queue.async { [self] in
            guard let device = videoInput?.device, (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = true }
            let center = CGPoint(x: 0.5, y: 0.5)
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = center }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = center }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.unlockForConfiguration()
        }
    }

    /// Whether the active input is a genuine built-in camera (not Continuity/USB/
    /// virtual). Reads on the session queue to avoid racing device configuration.
    public func isUsingTrustedCamera() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: videoInput?.device.isTrustedBuiltInCamera ?? false)
            }
        }
    }

    /// Restore continuous autofocus / auto-exposure after a stabilized capture.
    public func restoreContinuousFocus() {
        queue.async { [self] in
            guard let device = videoInput?.device,
                  (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.unlockForConfiguration()
        }
    }

    // MARK: - Controls

    public func switchCamera() {
        let newPosition: AVCaptureDevice.Position = position == .back ? .front : .back
        queue.async { [self] in
            session.beginConfiguration()
            if let videoInput { session.removeInput(videoInput) }
            if let device = Self.device(for: newPosition),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
                videoInput = input
            }
            session.commitConfiguration()
            Task { @MainActor in
                self.position = newPosition
                self.updateZoomRange()
                if let device = self.videoInput?.device, let layer = self.previewLayer {
                    self.createRotationCoordinator(for: device, previewLayer: layer)
                }
            }
        }
    }

    /// Set zoom, clamped to the device's supported range.
    public func setZoom(_ factor: CGFloat) {
        queue.async { [self] in
            guard let device = videoInput?.device else { return }
            let clamped = max(device.minAvailableVideoZoomFactor, min(factor, device.maxAvailableVideoZoomFactor))
            try? device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            Task { @MainActor in self.zoomFactor = clamped }
        }
    }

    /// Tap-to-focus using a point in the preview layer's coordinate space.
    public func focus(atViewPoint point: CGPoint) {
        guard let previewLayer else { return }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        queue.async { [self] in
            guard let device = videoInput?.device else { return }
            try? device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        }
    }

    public func setTorch(_ on: Bool) {
        queue.async { [self] in
            guard let device = videoInput?.device, device.hasTorch else { return }
            try? device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            Task { @MainActor in self.isTorchOn = on }
        }
    }

    // MARK: - Helpers

    private func updateZoomRange() {
        guard let device = videoInput?.device else { return }
        minZoomFactor = device.minAvailableVideoZoomFactor
        maxZoomFactor = min(device.maxAvailableVideoZoomFactor, 10)
        zoomFactor = device.videoZoomFactor
    }

    private func createRotationCoordinator(for device: AVCaptureDevice, previewLayer: AVCaptureVideoPreviewLayer) {
        rotationObservations.removeAll()
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator

        previewLayer.connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
        captureRotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture

        rotationObservations.append(
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, change in
                guard let angle = change.newValue else { return }
                Task { @MainActor in self?.previewLayer?.connection?.videoRotationAngle = angle }
            }
        )
        rotationObservations.append(
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, change in
                guard let angle = change.newValue else { return }
                Task { @MainActor in self?.captureRotationAngle = angle }
            }
        )
    }

    private var avFlashMode: AVCaptureDevice.FlashMode {
        switch flashMode {
        case .off:  return .off
        case .on:   return .on
        case .auto: return .auto
        }
    }

    nonisolated private static func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // Priority-ordered selection with a lockForConfiguration functionality probe.
        CameraDeviceDetector().detect(for: position).device
    }
}

/// A single live camera frame. `CMSampleBuffer`/`CVPixelBuffer` aren't `Sendable`,
/// but a frame is produced and consumed within one analysis hop, so this box is
/// safe to move across the frame `AsyncStream`.
public struct CameraFrame: @unchecked Sendable {
    public let sampleBuffer: CMSampleBuffer
    public init(sampleBuffer: CMSampleBuffer) { self.sampleBuffer = sampleBuffer }
    /// The underlying pixel buffer, ready for a `VNImageRequestHandler`.
    public var pixelBuffer: CVPixelBuffer? { CMSampleBufferGetImageBuffer(sampleBuffer) }
}

/// Forwards `AVCaptureVideoDataOutput` sample buffers to a `Sendable` handler.
/// `onFrame` is set on the main actor and read on the frame queue; a plain
/// reference assignment is atomic, so this fire-and-forget forwarding is sound.
final class FrameForwarder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    nonisolated(unsafe) var onFrame: (@Sendable (CMSampleBuffer) -> Void)?

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onFrame?(sampleBuffer)
    }
}

/// Bridges the photo-output callback into an `async` continuation.
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: (UIImage?) -> Void
    init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completion(nil)
            return
        }
        completion(image)
    }
}
