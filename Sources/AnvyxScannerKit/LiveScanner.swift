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

    /// Live mode; can be switched while scanning — the analysis loop reads it each frame.
    public var mode: Mode

    /// Detected document quads (document mode), normalized bottom-left, smoothed.
    public private(set) var quads: [DocumentQuad] = []
    /// Detected text-line boxes (text mode), normalized bottom-left.
    public private(set) var textLines: [TextLine] = []
    /// Aspect ratio (width / height) of the analyzed frame in display orientation —
    /// used to map normalized detections onto an aspect-fill preview.
    public private(set) var frameAspect: CGFloat = 3.0 / 4.0

    public let camera = CameraModel()

    private let documentDetector: DocumentQuadDetector
    private let textDetector: TextLineDetector
    private let orientation: CGImagePropertyOrientation
    /// Minimum seconds between analyses — caps Vision to ~this rate to save CPU
    /// (the camera runs faster; extra frames are skipped).
    private let analysisInterval: CFTimeInterval
    /// Frames are downscaled so their longest edge is at most this many pixels
    /// before analysis — cheaper Vision + less memory; quads are normalized so
    /// they still map back to the full preview.
    private let maxAnalysisDimension: CGFloat
    private let ciContext = LiveScanner.makeContext()
    private var scanTask: Task<Void, Never>?

    public init(mode: Mode = .document,
                maximumDocuments: Int = 3,
                orientation: CGImagePropertyOrientation = .right,
                analysisFrameRate: Double = 12,
                maxAnalysisDimension: CGFloat = 1024) {
        self.mode = mode
        self.orientation = orientation
        self.analysisInterval = analysisFrameRate > 0 ? 1.0 / analysisFrameRate : 0
        self.maxAnalysisDimension = maxAnalysisDimension
        self.documentDetector = DocumentQuadDetector(maximumDocuments: maximumDocuments)
        self.textDetector = TextLineDetector(recognitionLevel: .fast)
    }

    /// A Metal-backed context when available (fast, low-overhead), else the default.
    nonisolated static func makeContext() -> CIContext {
        if let device = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: device) }
        return CIContext(options: nil)
    }

    /// Configure + start the camera and begin live analysis.
    public func start() async {
        await camera.configure()
        camera.start()
        startScanning()
    }

    /// Stop analysis and the camera.
    public func stop() {
        scanTask?.cancel()
        scanTask = nil
        camera.stopVideoFrames()
        camera.stop()
    }

    private func startScanning() {
        scanTask?.cancel()
        // Value-type detectors are captured into the background task; only the
        // Sendable results are published back to the main actor.
        let documentDetector = self.documentDetector
        let textDetector = self.textDetector
        let orientation = self.orientation
        let interval = self.analysisInterval
        let maxDimension = self.maxAnalysisDimension
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let stream = await self?.camera.videoFrames() else { return }
            let handler = VNSequenceRequestHandler()   // reused across frames
            let context = LiveScanner.makeContext()
            var tracker = QuadTracker()   // hysteresis + grace + smoothing (anti-flicker)
            var lastAnalysis: CFTimeInterval = 0

            for await frame in stream {
                if Task.isCancelled { break }
                let now = CACurrentMediaTime()
                guard now - lastAnalysis >= interval else { continue }   // throttle → save CPU
                guard let pixelBuffer = frame.pixelBuffer,
                      let image = LiveScanner.analysisImage(from: pixelBuffer, orientation: orientation,
                                                            maxDimension: maxDimension, context: context)
                else { continue }
                lastAnalysis = now
                let aspect = CGFloat(image.width) / CGFloat(image.height)
                let mode = await self?.mode ?? .document

                switch mode {
                case .document:
                    let scored = (try? documentDetector.detectScored(in: image, using: handler)) ?? []
                    await self?.publish(quads: tracker.update(scored), textLines: [], aspect: aspect)
                case .singleDocument:
                    var scored: [ScoredQuad] = []
                    if #available(iOS 26, *) {
                        if let quad = try? await DocumentEdgeDetector().detectQuad(in: image) {
                            scored = [ScoredQuad(quad: quad, confidence: 1)]   // segmentation is decisive
                        }
                    } else {
                        scored = Array(((try? documentDetector.detectScored(in: image, using: handler)) ?? []).prefix(1))
                    }
                    await self?.publish(quads: tracker.update(scored), textLines: [], aspect: aspect)
                case .text:
                    tracker.reset()
                    let lines = (try? textDetector.detect(in: image, using: handler)) ?? []
                    await self?.publish(quads: [], textLines: lines, aspect: aspect)
                }
            }
        }
    }

    /// Build an oriented, downscaled `CGImage` for analysis from a camera frame.
    nonisolated static func analysisImage(from pixelBuffer: CVPixelBuffer,
                                          orientation: CGImagePropertyOrientation,
                                          maxDimension: CGFloat,
                                          context: CIContext) -> CGImage? {
        var image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        let longest = max(image.extent.width, image.extent.height)
        if longest > maxDimension, longest > 0 {
            let scale = maxDimension / longest
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return context.createCGImage(image, from: image.extent)
    }

    private func publish(quads: [DocumentQuad], textLines: [TextLine], aspect: CGFloat) {
        frameAspect = aspect
        // Skip redundant "nothing detected" updates to avoid needless re-renders.
        if quads.isEmpty, textLines.isEmpty, self.quads.isEmpty, self.textLines.isEmpty { return }
        self.quads = quads
        self.textLines = textLines
    }

    /// Capture a full-resolution photo. In document mode this returns every
    /// detected document, perspective-corrected to an upright rectangle; in text
    /// mode it returns the single captured photo. Empty if capture failed.
    public func capture() async -> [UIImage] {
        guard let photo = await camera.capturePhoto(), let cgImage = photo.cgImage else { return [] }
        guard mode != .text else { return [photo] }

        // Single-document: prefer the iOS 26 segmentation model for a precise quad.
        if mode == .singleDocument, #available(iOS 26, *),
           let quad = try? await DocumentEdgeDetector().detectQuad(in: cgImage),
           let corrected = DocumentPerspective.corrected(cgImage, quad: quad, context: ciContext) {
            return [UIImage(cgImage: corrected, scale: photo.scale, orientation: .up)]
        }

        let detected = (try? documentDetector.detect(in: cgImage)) ?? []
        let quads = mode == .singleDocument ? Array(detected.prefix(1)) : detected
        guard !quads.isEmpty else { return [photo] }
        return quads.compactMap { quad in
            DocumentPerspective.corrected(cgImage, quad: quad, context: ciContext)
                .map { UIImage(cgImage: $0, scale: photo.scale, orientation: .up) }
        }
    }
}
