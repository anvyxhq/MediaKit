//
//  TextLineDetector.swift
//  ScannerKit
//
//  Created by AnhPT on 13/07/2026.
//

import Vision
import CoreGraphics
import CoreVideo
import CoreImage

/// A recognized line of text on the camera frame.
public struct TextLine: Sendable, Equatable {
    /// Bounding box, normalized to `0…1` with a bottom-left origin (Vision convention).
    public var boundingBox: CGRect
    /// The recognized string, when text was read (`nil` in fast/geometry-only passes).
    public var text: String?

    public init(boundingBox: CGRect, text: String? = nil) {
        self.boundingBox = boundingBox
        self.text = text
    }
}

/// Detects lines of text and returns their bounding boxes — the basis for drawing
/// a live underline under each line on the preview.
public struct TextLineDetector: Sendable {
    /// `.fast` for live overlays; `.accurate` when you also need the text.
    public var recognitionLevel: VNRequestTextRecognitionLevel
    /// Read the actual strings (slower). Off by default for smooth live underlining.
    public var readsText: Bool
    /// Ignore text shorter than this fraction of the image height — skips tiny,
    /// far-away text for speed.
    public var minimumTextHeight: Float
    /// Languages to consider (empty = Vision's default). Fewer = faster.
    public var recognitionLanguages: [String]
    /// Restrict recognition to this normalized region (bottom-left origin).
    public var regionOfInterest: CGRect?

    public init(recognitionLevel: VNRequestTextRecognitionLevel = .fast,
                readsText: Bool = false,
                minimumTextHeight: Float = 0.02,
                recognitionLanguages: [String] = [],
                regionOfInterest: CGRect? = nil) {
        self.recognitionLevel = recognitionLevel
        self.readsText = readsText
        self.minimumTextHeight = minimumTextHeight
        self.recognitionLanguages = recognitionLanguages
        self.regionOfInterest = regionOfInterest
    }

    private func makeRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = readsText
        request.minimumTextHeight = minimumTextHeight
        if !recognitionLanguages.isEmpty { request.recognitionLanguages = recognitionLanguages }
        if let regionOfInterest { request.regionOfInterest = regionOfInterest }
        return request
    }

    private func lines(from request: VNRecognizeTextRequest) -> [TextLine] {
        (request.results ?? []).map { observation in
            TextLine(boundingBox: observation.boundingBox,
                     text: readsText ? observation.topCandidates(1).first?.string : nil)
        }
    }

    /// Detect text lines in a still image.
    public func detect(in image: CGImage) throws -> [TextLine] {
        let request = makeRequest()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return lines(from: request)
    }

    /// Detect text lines in a live camera frame, reusing a `VNSequenceRequestHandler`
    /// across frames.
    public func detect(in pixelBuffer: CVPixelBuffer,
                       orientation: CGImagePropertyOrientation,
                       using handler: VNSequenceRequestHandler) throws -> [TextLine] {
        let request = makeRequest()
        try handler.perform([request], on: pixelBuffer, orientation: orientation)
        return lines(from: request)
    }

    /// Detect text lines in an already-oriented (usually downscaled) frame image,
    /// reusing a `VNSequenceRequestHandler`.
    public func detect(in image: CGImage,
                       orientation: CGImagePropertyOrientation = .up,
                       using handler: VNSequenceRequestHandler) throws -> [TextLine] {
        let request = makeRequest()
        try handler.perform([request], on: image, orientation: orientation)
        return lines(from: request)
    }

    /// Detect text lines on a `CIImage` (avoids a per-frame `CGImage` allocation).
    public func detect(in image: CIImage,
                       orientation: CGImagePropertyOrientation = .up,
                       using handler: VNSequenceRequestHandler) throws -> [TextLine] {
        let request = makeRequest()
        try handler.perform([request], on: image, orientation: orientation)
        return lines(from: request)
    }
}
