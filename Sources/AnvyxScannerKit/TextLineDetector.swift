//
//  TextLineDetector.swift
//  ScannerKit
//
//  Created by AnhPT on 13/07/2026.
//

import Vision
import CoreGraphics
import CoreVideo

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

    public init(recognitionLevel: VNRequestTextRecognitionLevel = .fast, readsText: Bool = false) {
        self.recognitionLevel = recognitionLevel
        self.readsText = readsText
    }

    private func makeRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = readsText
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

    /// Detect text lines in a live camera frame.
    public func detect(in pixelBuffer: CVPixelBuffer,
                       orientation: CGImagePropertyOrientation = .right) throws -> [TextLine] {
        let request = makeRequest()
        try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:]).perform([request])
        return lines(from: request)
    }
}
