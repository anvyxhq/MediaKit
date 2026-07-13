//
//  LiveScanner.swift
//  ScannerKit
//
//  Created by AnhPT on 13/07/2026.
//

import UIKit
import AVFoundation
import CoreImage
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

    /// Switching mode restarts the live analysis stream.
    public var mode: Mode { didSet { if mode != oldValue { restartStream() } } }

    /// Detected document quads (document mode), normalized bottom-left.
    public private(set) var quads: [DocumentQuad] = []
    /// Detected text-line boxes (text mode), normalized bottom-left.
    public private(set) var textLines: [TextLine] = []

    public let camera = CameraModel()

    private let documentDetector: DocumentQuadDetector
    private let textDetector: TextLineDetector
    private let ciContext = CIContext(options: nil)
    private var running = false

    public init(mode: Mode = .document, maximumDocuments: Int = 3) {
        self.mode = mode
        self.documentDetector = DocumentQuadDetector(maximumDocuments: maximumDocuments)
        self.textDetector = TextLineDetector(recognitionLevel: .fast)
    }

    /// Configure + start the camera and begin live analysis.
    public func start() async {
        await camera.configure()
        camera.start()
        running = true
        startStream()
    }

    /// Stop analysis and the camera.
    public func stop() {
        running = false
        camera.stopVideoFrames()
        camera.stop()
    }

    private func startStream() {
        // Capture value-type detectors so the background frame closure never
        // touches main-actor state directly (only publishes Sendable results).
        let mode = self.mode
        let documentDetector = self.documentDetector
        let textDetector = self.textDetector
        camera.startVideoFrames { [weak self] sampleBuffer in
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            switch mode {
            case .document:
                let quads = (try? documentDetector.detect(in: pixelBuffer)) ?? []
                Task { @MainActor in self?.publish(quads: quads, textLines: []) }
            case .text:
                let lines = (try? textDetector.detect(in: pixelBuffer)) ?? []
                Task { @MainActor in self?.publish(quads: [], textLines: lines) }
            }
        }
    }

    private func restartStream() {
        guard running else { return }
        camera.stopVideoFrames()
        quads = []; textLines = []
        startStream()
    }

    private func publish(quads: [DocumentQuad], textLines: [TextLine]) {
        self.quads = quads
        self.textLines = textLines
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
