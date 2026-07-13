//
//  DocumentQuadDetector.swift
//  ScannerKit
//
//  Created by AnhPT on 13/07/2026.
//

import Vision
import CoreGraphics
import CoreVideo
import AnvyxCropKit

/// Detects one or more rectangular documents in a frame and returns their corner
/// quads (normalized, bottom-left origin — the same convention as CropKit's
/// ``DocumentQuad``, so results feed straight into `DocumentPerspective`).
///
/// Uses `VNDetectRectanglesRequest`, which returns *multiple* candidates — the
/// basis for showing several document frames on the live preview at once.
public struct DocumentQuadDetector: Sendable {
    /// Maximum number of documents to report per frame.
    public var maximumDocuments: Int
    /// Minimum detector confidence (`0…1`) to keep a candidate.
    public var minimumConfidence: VNConfidence
    /// Smallest accepted width/height ratio — filters out slivers.
    public var minimumAspectRatio: Float
    /// Smallest accepted size as a fraction of the image's shorter side.
    public var minimumSize: Float

    public init(
        maximumDocuments: Int = 3,
        minimumConfidence: VNConfidence = 0.6,
        minimumAspectRatio: Float = 0.3,
        minimumSize: Float = 0.2
    ) {
        self.maximumDocuments = maximumDocuments
        self.minimumConfidence = minimumConfidence
        self.minimumAspectRatio = minimumAspectRatio
        self.minimumSize = minimumSize
    }

    private func makeRequest() -> VNDetectRectanglesRequest {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = maximumDocuments
        request.minimumConfidence = minimumConfidence
        request.minimumAspectRatio = minimumAspectRatio
        request.minimumSize = minimumSize
        request.quadratureTolerance = 25
        return request
    }

    private func quads(from request: VNDetectRectanglesRequest) -> [DocumentQuad] {
        (request.results ?? [])
            .sorted { $0.confidence > $1.confidence }
            .map {
                DocumentQuad(topLeft: $0.topLeft, topRight: $0.topRight,
                             bottomLeft: $0.bottomLeft, bottomRight: $0.bottomRight)
            }
    }

    /// Detect documents in a still image.
    public func detect(in image: CGImage) throws -> [DocumentQuad] {
        let request = makeRequest()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return quads(from: request)
    }

    /// Detect documents in a live camera frame, reusing a `VNSequenceRequestHandler`
    /// across frames — smoother and cheaper than a fresh handler each frame.
    public func detect(in pixelBuffer: CVPixelBuffer,
                       orientation: CGImagePropertyOrientation,
                       using handler: VNSequenceRequestHandler) throws -> [DocumentQuad] {
        let request = makeRequest()
        try handler.perform([request], on: pixelBuffer, orientation: orientation)
        return quads(from: request)
    }

    /// Detect documents in an already-oriented (usually downscaled) frame image,
    /// reusing a `VNSequenceRequestHandler`.
    public func detect(in image: CGImage,
                       orientation: CGImagePropertyOrientation = .up,
                       using handler: VNSequenceRequestHandler) throws -> [DocumentQuad] {
        let request = makeRequest()
        try handler.perform([request], on: image, orientation: orientation)
        return quads(from: request)
    }
}
