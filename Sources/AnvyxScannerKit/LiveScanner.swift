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
import Observation
import AnvyxCameraKit
import AnvyxCropKit

/// Drives the camera and live Vision analysis for a document/text scanner, and
/// exposes the results for an overlay to draw. Feed ``camera`` to a
/// `CameraPreview` and ``quads`` / ``textLines`` to a ``ScannerOverlay``.
@MainActor
@Observable
public final class LiveScanner {
    public enum Mode: Sendable, Equatable { case document, text }

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
    private let ciContext = CIContext(options: nil)
    private var scanTask: Task<Void, Never>?

    public init(mode: Mode = .document,
                maximumDocuments: Int = 3,
                orientation: CGImagePropertyOrientation = .right) {
        self.mode = mode
        self.orientation = orientation
        self.documentDetector = DocumentQuadDetector(maximumDocuments: maximumDocuments)
        self.textDetector = TextLineDetector(recognitionLevel: .fast)
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
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let stream = await self?.camera.videoFrames() else { return }
            let handler = VNSequenceRequestHandler()   // reused across frames — smoother
            var smoother = QuadSmoother()
            for await frame in stream {
                if Task.isCancelled { break }
                guard let pixelBuffer = frame.pixelBuffer else { continue }
                let mode = await self?.mode ?? .document
                let aspect = Self.orientedAspect(of: pixelBuffer, orientation: orientation)
                switch mode {
                case .document:
                    let raw = (try? documentDetector.detect(in: pixelBuffer, orientation: orientation, using: handler)) ?? []
                    let smoothed = smoother.update(raw)
                    await self?.publish(quads: smoothed, textLines: [], aspect: aspect)
                case .text:
                    smoother.reset()
                    let lines = (try? textDetector.detect(in: pixelBuffer, orientation: orientation, using: handler)) ?? []
                    await self?.publish(quads: [], textLines: lines, aspect: aspect)
                }
            }
        }
    }

    private func publish(quads: [DocumentQuad], textLines: [TextLine], aspect: CGFloat) {
        self.quads = quads
        self.textLines = textLines
        self.frameAspect = aspect
    }

    /// The analyzed frame's aspect ratio (width/height) in display orientation.
    nonisolated static func orientedAspect(of pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> CGFloat {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard width > 0, height > 0 else { return 3.0 / 4.0 }
        switch orientation {
        case .right, .left, .rightMirrored, .leftMirrored:
            return height / width   // sensor rotated 90° → swap
        default:
            return width / height
        }
    }

    /// Capture a full-resolution photo. In document mode this returns every
    /// detected document, perspective-corrected to an upright rectangle; in text
    /// mode it returns the single captured photo. Empty if capture failed.
    public func capture() async -> [UIImage] {
        guard let photo = await camera.capturePhoto(), let cgImage = photo.cgImage else { return [] }
        guard mode == .document else { return [photo] }

        let quads = (try? documentDetector.detect(in: cgImage)) ?? []
        guard !quads.isEmpty else { return [photo] }
        return quads.compactMap { quad in
            DocumentPerspective.corrected(cgImage, quad: quad, context: ciContext)
                .map { UIImage(cgImage: $0, scale: photo.scale, orientation: .up) }
        }
    }
}
