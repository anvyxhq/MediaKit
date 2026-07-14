//
//  LiveScanner.swift
//  ScannerKit
//
//  Created by AnhPT on 13/07/2026.
//

import UIKit
import AVFoundation
import CoreImage
import CoreVideo
import Vision
import Metal
import QuartzCore
import Observation
import os
import AnvyxCameraKit
import AnvyxCropKit

/// Drives the camera and live Vision analysis for a document/text scanner, and
/// exposes the results for an overlay to draw. Feed ``camera`` to a
/// `CameraPreview` and ``quads`` / ``textLines`` to a ``ScannerOverlay``.
@MainActor
@Observable
public final class LiveScanner {
    public enum Mode: Sendable, Equatable {
        /// Detect multiple rectangular documents at once (`VNDetectRectangles`).
        case document
        /// Detect a single document with the iOS 26 segmentation model — precise
        /// edges on complex backgrounds (falls back to rectangles pre-iOS 26).
        case singleDocument
        /// Detect text lines for live underlining.
        case text
    }

    /// A Sendable snapshot the background loop reads each frame without hopping
    /// to the main actor.
    struct Snapshot: Sendable {
        var mode: Mode
        var orientation: CGImagePropertyOrientation
        var autoCapture: Bool
    }

    /// Live mode; can be switched while scanning.
    public var mode: Mode { didSet { let mode = mode; snapshot.withLock { $0.mode = mode } } }

    /// When on, the scanner auto-captures once a document is held steady (document
    /// modes only). Toggle any time.
    public var autoCaptureEnabled: Bool {
        didSet { let value = autoCaptureEnabled; snapshot.withLock { $0.autoCapture = value } }
    }

    /// Called on the main actor with the auto-captured pages.
    public var onAutoCapture: (([UIImage]) -> Void)?

    /// Detected document quads (document mode), normalized bottom-left, stabilized.
    public private(set) var quads: [DocumentQuad] = []
    /// Detected text-line boxes (text mode), normalized bottom-left.
    public private(set) var textLines: [TextLine] = []
    /// Aspect ratio (width / height) of the analyzed frame in display orientation.
    public private(set) var frameAspect: CGFloat = 3.0 / 4.0
    /// Live guidance for the user (brightness / framing), e.g. "Move closer".
    public private(set) var guidance: ScanGuidance = .searching

    // Guidance tuning.
    public var darkThreshold: CGFloat = 0.22
    public var brightThreshold: CGFloat = 0.92
    public var nearAreaThreshold: CGFloat = 0.85   // above → too close
    public var farAreaThreshold: CGFloat = 0.18    // below → too far

    public let camera = CameraModel()

    private let documentDetector: DocumentQuadDetector
    private let textDetector: TextLineDetector
    private let analysisInterval: CFTimeInterval
    private let maxAnalysisDimension: CGFloat
    private let ciContext = LiveScanner.makeContext()
    private let snapshot: OSAllocatedUnfairLock<Snapshot>
    private var scanTask: Task<Void, Never>?
    private var orientationTask: Task<Void, Never>?

    // Auto-capture tuning.
    /// How long a document must be held steady before auto-capturing (seconds).
    public var autoCaptureHoldDuration: CFTimeInterval = 0.8
    /// Max normalized centroid movement still considered "steady".
    public var autoCaptureMovementThreshold: CGFloat = 0.02
    private let autoCaptureCooldown: CFTimeInterval = 1.5
    private var isCapturing = false
    private var lastAutoCaptureTime: CFTimeInterval = 0

    public init(mode: Mode = .document,
                autoCapture: Bool = false,
                maximumDocuments: Int = 3,
                analysisFrameRate: Double = 12,
                maxAnalysisDimension: CGFloat = 1024) {
        self.mode = mode
        self.autoCaptureEnabled = autoCapture
        self.analysisInterval = analysisFrameRate > 0 ? 1.0 / analysisFrameRate : 0
        self.maxAnalysisDimension = maxAnalysisDimension
        self.documentDetector = DocumentQuadDetector(maximumDocuments: maximumDocuments)
        self.textDetector = TextLineDetector(recognitionLevel: .fast)
        self.snapshot = OSAllocatedUnfairLock(initialState: Snapshot(mode: mode, orientation: .right, autoCapture: autoCapture))
    }

    /// A Metal-backed context when available (fast, low-overhead), else the default.
    nonisolated static func makeContext() -> CIContext {
        if let device = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: device) }
        return CIContext(options: nil)
    }

    // MARK: - Lifecycle

    /// Configure (once) + start the camera and begin live analysis. Cheap to call
    /// again to resume after ``stop()``.
    public func start() async {
        if !camera.isConfigured { await camera.configure() }
        camera.start()
        observeOrientation()
        startScanning()
    }

    /// Stop analysis and the camera (keeps configuration so ``start()`` resumes fast).
    public func stop() {
        scanTask?.cancel(); scanTask = nil
        orientationTask?.cancel(); orientationTask = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        camera.stopVideoFrames()
        camera.stop()
    }

    // MARK: - Orientation

    private func observeOrientation() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        updateOrientation()
        orientationTask?.cancel()
        orientationTask = Task { @MainActor [weak self] in
            let notifications = NotificationCenter.default.notifications(named: UIDevice.orientationDidChangeNotification)
            for await _ in notifications { self?.updateOrientation() }
        }
    }

    private func updateOrientation() {
        let device = UIDevice.current.orientation
        guard device.isValidInterfaceOrientation else { return }   // ignore face up/down
        let orientation = Self.visionOrientation(device: device, position: camera.position)
        snapshot.withLock { $0.orientation = orientation }
    }

    /// Map a device orientation to the Vision image orientation for a camera.
    nonisolated static func visionOrientation(device: UIDeviceOrientation,
                                              position: AVCaptureDevice.Position) -> CGImagePropertyOrientation {
        let back: CGImagePropertyOrientation
        switch device {
        case .portrait:            back = .right
        case .portraitUpsideDown:  back = .left
        case .landscapeLeft:       back = .up
        case .landscapeRight:      back = .down
        default:                   back = .right
        }
        // The front camera is mirrored horizontally relative to the back camera.
        guard position == .front else { return back }
        switch back {
        case .right: return .leftMirrored
        case .left:  return .rightMirrored
        case .up:    return .upMirrored
        case .down:  return .downMirrored
        default:     return back
        }
    }

    // MARK: - Analysis loop

    private func startScanning() {
        scanTask?.cancel()
        let documentDetector = self.documentDetector
        let textDetector = self.textDetector
        let baseInterval = self.analysisInterval
        let maxDimension = self.maxAnalysisDimension
        let snapshot = self.snapshot
        let holdDuration = self.autoCaptureHoldDuration
        let movementThreshold = self.autoCaptureMovementThreshold
        let dark = self.darkThreshold, bright = self.brightThreshold
        let nearArea = self.nearAreaThreshold, farArea = self.farAreaThreshold
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let stream = await self?.camera.videoFrames() else { return }
            let handler = VNSequenceRequestHandler()
            let context = LiveScanner.makeContext()
            var tracker = QuadTracker()
            var lastAnalysis: CFTimeInterval = 0
            var idleFrames = 0
            var steadyCentroid: CGPoint?
            var steadyCount = -1
            var steadySince: CFTimeInterval = 0

            for await frame in stream {
                if Task.isCancelled { break }
                // Adaptive throttle: analyze slower when nothing's been found lately.
                let interval = idleFrames >= 15 ? baseInterval * 2 : baseInterval
                let now = CACurrentMediaTime()
                guard now - lastAnalysis >= interval else { continue }
                guard let pixelBuffer = frame.pixelBuffer else { continue }
                lastAnalysis = now

                let snap = snapshot.withLock { $0 }
                let image = LiveScanner.analysisImage(from: pixelBuffer, orientation: snap.orientation,
                                                      maxDimension: maxDimension)
                let aspect = image.extent.height > 0 ? image.extent.width / image.extent.height : 3.0 / 4.0

                // Cheap brightness pre-gate: skip the model on unusable frames.
                let brightness = FrameQuality.averageBrightness(of: pixelBuffer)
                if brightness < dark {
                    steadyCentroid = nil
                    await self?.publish(quads: [], textLines: [], aspect: aspect, guidance: .tooDark)
                    continue
                }
                if brightness > bright {
                    steadyCentroid = nil
                    await self?.publish(quads: [], textLines: [], aspect: aspect, guidance: .tooBright)
                    continue
                }

                var quads: [DocumentQuad] = []
                var lines: [TextLine] = []
                switch snap.mode {
                case .document:
                    let scored = (try? documentDetector.detectScored(in: image, using: handler)) ?? []
                    quads = tracker.update(scored)
                case .singleDocument:
                    var scored: [ScoredQuad] = []
                    if #available(iOS 26, *) {
                        if let cgImage = context.createCGImage(image, from: image.extent),
                           let quad = try? await DocumentEdgeDetector().detectQuad(in: cgImage) {
                            scored = [ScoredQuad(quad: quad, confidence: 1)]
                        }
                    } else {
                        scored = Array(((try? documentDetector.detectScored(in: image, using: handler)) ?? []).prefix(1))
                    }
                    quads = tracker.update(scored)
                case .text:
                    tracker.reset()
                    lines = (try? textDetector.detect(in: image, using: handler)) ?? []
                }

                // Steadiness of the whole set (count + average centroid) — works
                // for one or many documents.
                var steadyEnough = false
                let setCentroid = quads.isEmpty ? nil
                    : quads.reduce(CGPoint.zero) { CGPoint(x: $0.x + QuadTracker.centroid($1).x,
                                                           y: $0.y + QuadTracker.centroid($1).y) }
                        .applying(CGAffineTransform(scaleX: 1.0 / CGFloat(quads.count), y: 1.0 / CGFloat(quads.count)))
                if let centroid = setCentroid, quads.count == steadyCount,
                   let previous = steadyCentroid,
                   hypot(centroid.x - previous.x, centroid.y - previous.y) < movementThreshold {
                    steadyEnough = now - steadySince >= holdDuration
                } else if let centroid = setCentroid {
                    steadyCentroid = centroid; steadyCount = quads.count; steadySince = now
                } else {
                    steadyCentroid = nil; steadyCount = -1
                }

                // Guidance — distance framing only makes sense for a single document;
                // multi-doc just reports searching / hold / ready.
                var guidance: ScanGuidance = .searching
                switch snap.mode {
                case .text:
                    guidance = lines.isEmpty ? .searching : .ready
                case .singleDocument:
                    if let primary = quads.first {
                        let area = FrameQuality.area(of: primary)
                        if area > nearArea { guidance = .moveAway }
                        else if area < farArea { guidance = .moveCloser }
                        else { guidance = steadyEnough ? .ready : .holdSteady }
                    }
                case .document:
                    if !quads.isEmpty { guidance = steadyEnough ? .ready : .holdSteady }
                }

                idleFrames = (quads.isEmpty && lines.isEmpty) ? idleFrames + 1 : 0
                await self?.publish(quads: quads, textLines: lines, aspect: aspect, guidance: guidance)

                if snap.autoCapture, steadyEnough, !quads.isEmpty {
                    steadyCentroid = nil; steadyCount = -1   // require re-steadying before the next shot
                    await self?.performAutoCapture()
                }
            }
        }
    }

    private func performAutoCapture() async {
        guard !isCapturing, autoCaptureEnabled else { return }
        let now = CACurrentMediaTime()
        guard now - lastAutoCaptureTime > autoCaptureCooldown else { return }
        isCapturing = true
        let images = await capture()
        isCapturing = false
        lastAutoCaptureTime = CACurrentMediaTime()
        if !images.isEmpty { onAutoCapture?(images) }
    }

    /// Build an oriented, downscaled `CIImage` for analysis (no `CGImage` allocation).
    nonisolated static func analysisImage(from pixelBuffer: CVPixelBuffer,
                                          orientation: CGImagePropertyOrientation,
                                          maxDimension: CGFloat) -> CIImage {
        var image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        let longest = max(image.extent.width, image.extent.height)
        if longest > maxDimension, longest > 0 {
            let scale = maxDimension / longest
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return image
    }

    private func publish(quads: [DocumentQuad], textLines: [TextLine], aspect: CGFloat, guidance: ScanGuidance) {
        frameAspect = aspect
        if guidance != self.guidance { self.guidance = guidance }
        if quads.isEmpty, textLines.isEmpty, self.quads.isEmpty, self.textLines.isEmpty { return }
        self.quads = quads
        self.textLines = textLines
    }

    // MARK: - Capture

    /// Capture a full-resolution photo. Document modes return every detected
    /// document, perspective-corrected; text mode returns the photo. Detection
    /// runs on a downscaled copy for speed, correction on the full-res image.
    public func capture() async -> [UIImage] {
        // Wait for focus/exposure to settle so the photo is sharp, then restore AF.
        await camera.lockFocusAndExposureWhenStable()
        let photo = await camera.capturePhoto()
        camera.restoreContinuousFocus()
        guard let photo, let full = photo.cgImage else { return [] }
        guard mode != .text else { return [photo] }

        let small = downscaledForDetection(full)

        if mode == .singleDocument, #available(iOS 26, *),
           let quad = try? await DocumentEdgeDetector().detectQuad(in: small),
           let corrected = DocumentPerspective.corrected(full, quad: quad, context: ciContext) {
            return [UIImage(cgImage: corrected, scale: photo.scale, orientation: .up)]
        }

        let handler = VNSequenceRequestHandler()
        let detected = (try? documentDetector.detectScored(in: small, using: handler)) ?? []
        let quads = (mode == .singleDocument ? Array(detected.prefix(1)) : detected).map(\.quad)
        guard !quads.isEmpty else { return [photo] }
        return quads.compactMap { quad in
            DocumentPerspective.corrected(full, quad: quad, context: ciContext)
                .map { UIImage(cgImage: $0, scale: photo.scale, orientation: .up) }
        }
    }

    private func downscaledForDetection(_ image: CGImage, maxDimension: CGFloat = 1536) -> CGImage {
        var ciImage = CIImage(cgImage: image)
        let longest = max(ciImage.extent.width, ciImage.extent.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return ciContext.createCGImage(ciImage, from: ciImage.extent) ?? image
    }
}
