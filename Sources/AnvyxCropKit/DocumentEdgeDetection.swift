//
//  DocumentEdgeDetection.swift
//  CropKit
//
//  Created by AnhPT on 13/07/2026.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import CoreVideo
import Vision

/// The four corners of a detected document, **normalized** to `0...1` with a
/// bottom-left origin (Vision / Core Image convention).
public struct DocumentQuad: Sendable, Equatable {
    public var topLeft: CGPoint
    public var topRight: CGPoint
    public var bottomLeft: CGPoint
    public var bottomRight: CGPoint

    public init(topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }
}

/// Flattens the region inside a ``DocumentQuad`` into an upright rectangle via
/// Core Image perspective correction — no Vision required, so it's usable on its
/// own once you have a quad.
public enum DocumentPerspective {
    public static func corrected(
        _ image: CGImage,
        quad: DocumentQuad,
        context: CIContext = CIContext(options: nil)
    ) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        func pixel(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * width, y: point.y * height) }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = CIImage(cgImage: image)
        filter.topLeft = pixel(quad.topLeft)
        filter.topRight = pixel(quad.topRight)
        filter.bottomLeft = pixel(quad.bottomLeft)
        filter.bottomRight = pixel(quad.bottomRight)

        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent)
    }
}

/// Detects the horizon tilt of a photo for one-tap auto-straightening, using
/// Vision's classic `VNDetectHorizonRequest` (available since iOS 11, so unlike
/// ``DocumentEdgeDetector`` it needs no availability gate).
public enum HorizonDetector {
    /// The roll angle (in radians) to apply so the detected horizon becomes level,
    /// or `nil` when no horizon is found. Runs synchronously — call it off the main
    /// actor (e.g. inside `Task.detached`) for large images.
    public nonisolated static func levelingAngle(in image: CGImage) -> CGFloat? {
        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let observation = request.results?.first else { return nil }
        // `angle` is the horizon's roll; negate it to level the image.
        return -CGFloat(observation.angle)
    }
}

/// Detects a document's edges in an image using Vision's
/// `DetectDocumentSegmentationRequest`, returning its corner quad — the basis for
/// an auto-crop / perspective-correct scan. iOS 26+.
@available(iOS 26, *)
public struct DocumentEdgeDetector: Sendable {
    public init() {}

    /// The detected document quad, or `nil` when no document is found.
    public func detectQuad(in image: CGImage) async throws -> DocumentQuad? {
        let request = DetectDocumentSegmentationRequest()
        guard let document = try await request.perform(on: image) else { return nil }
        return Self.quad(from: document)
    }

    /// Detect the document quad in a live camera frame (pixel buffer), or `nil`.
    public func detectQuad(in pixelBuffer: sending CVPixelBuffer,
                           orientation: CGImagePropertyOrientation = .up) async throws -> DocumentQuad? {
        let request = DetectDocumentSegmentationRequest()
        guard let document = try await request.perform(on: pixelBuffer, orientation: orientation) else { return nil }
        return Self.quad(from: document)
    }

    private static func quad(from document: DetectedDocumentObservation) -> DocumentQuad {
        DocumentQuad(
            topLeft: document.topLeft.cgPoint,
            topRight: document.topRight.cgPoint,
            bottomLeft: document.bottomLeft.cgPoint,
            bottomRight: document.bottomRight.cgPoint)
    }

    /// Detect the document and return a flattened, perspective-corrected image, or
    /// `nil` if no document is detected.
    public func correctedImage(
        from image: CGImage,
        context: CIContext = CIContext(options: nil)
    ) async throws -> CGImage? {
        guard let quad = try await detectQuad(in: image) else { return nil }
        return DocumentPerspective.corrected(image, quad: quad, context: context)
    }
}
