//
//  CVPixelBuffer+ImageKit.swift
//  ImageKit
//
//  Created by AnhPT on 03/07/2026.
//

import CoreImage
import CoreVideo
import UIKit

public extension CVPixelBuffer {

    // MARK: - Geometry

    var pixelWidth: Int { CVPixelBufferGetWidth(self) }
    var pixelHeight: Int { CVPixelBufferGetHeight(self) }
    var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }
    var bytesPerRow: Int { CVPixelBufferGetBytesPerRow(self) }

    /// The buffer's bounds as a `CGRect` (`.zero` if empty).
    var rect: CGRect {
        guard pixelWidth > 0, pixelHeight > 0 else { return .zero }
        return CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
    }

    // MARK: - Conversion

    /// Render the buffer to a `UIImage` using the shared `CIContext`.
    func toUIImage() -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: self)
        guard let cgImage = SharedCIContext.context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// PNG-encoded data for the buffer, or `nil` if rendering fails.
    func pngData(scale: CGFloat = UIScreen.main.scale) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: self)
        guard let cgImage = SharedCIContext.context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up).pngData()
    }

    // MARK: - Copy & crop

    /// A deep copy of the buffer (handles both packed and planar formats).
    func copy() -> CVPixelBuffer? {
        precondition(CFGetTypeID(self) == CVPixelBufferGetTypeID(), "copy() must be called on a CVPixelBuffer")

        var out: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            CVPixelBufferGetWidth(self),
            CVPixelBufferGetHeight(self),
            CVPixelBufferGetPixelFormatType(self),
            nil,
            &out
        )
        guard let copy = out else { return nil }

        CVPixelBufferLockBaseAddress(self, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(self, .readOnly)
            CVPixelBufferUnlockBaseAddress(copy, [])
        }

        if let source = CVPixelBufferGetBaseAddress(self),
           let destination = CVPixelBufferGetBaseAddress(copy) {
            let planeCount = CVPixelBufferGetPlaneCount(self)
            if planeCount == 0 {
                memcpy(destination, source, CVPixelBufferGetDataSize(self))
            } else {
                for plane in 0..<planeCount {
                    let dest = CVPixelBufferGetBaseAddressOfPlane(copy, plane)
                    let src = CVPixelBufferGetBaseAddressOfPlane(self, plane)
                    let height = CVPixelBufferGetHeightOfPlane(self, plane)
                    let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(self, plane)
                    memcpy(dest, src, height * rowBytes)
                }
            }
        }
        return copy
    }

    /// Crop the buffer to `rect` (in pixel coordinates), clamped to bounds.
    /// Returns a new `kCVPixelFormatType_32BGRA` buffer.
    func cropped(to rect: CGRect) -> CVPixelBuffer? {
        let w = CGFloat(pixelWidth), h = CGFloat(pixelHeight)
        let x = max(0, min(w, rect.origin.x))
        let y = max(0, min(h, rect.origin.y))
        let cw = min(rect.width, w - x)
        let ch = min(rect.height, h - y)
        guard cw > 0, ch > 0 else { return nil }

        // CoreImage's y-axis is bottom-up; flip the crop rect.
        let ciImage = CIImage(cvPixelBuffer: self)
            .cropped(to: CGRect(x: x, y: h - y - ch, width: cw, height: ch))
        let normalized = ciImage.transformed(by: CGAffineTransform(translationX: -ciImage.extent.origin.x,
                                                                   y: -ciImage.extent.origin.y))
        var out: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, Int(cw), Int(ch),
                            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
        guard let buffer = out else { return nil }
        SharedCIContext.context.render(normalized, to: buffer)
        return buffer
    }

    // MARK: - Analysis

    /// Average luminance in `0...1`, sampling every `samplingStep` pixels.
    ///
    /// Assumes a 32-bit BGRA layout (the common capture format). `samplingStep`
    /// trades accuracy for speed; the default of 10 is plenty for exposure checks.
    func averageBrightness(samplingStep: Int = 10) -> Float {
        CVPixelBufferLockBaseAddress(self, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(self) else { return 0 }
        let width = pixelWidth, height = pixelHeight, rowBytes = bytesPerRow
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var total: Float = 0
        var count = 0
        let step = max(1, samplingStep)
        for row in stride(from: 0, to: height, by: step) {
            let rowOffset = row * rowBytes
            for col in stride(from: 0, to: width, by: step) {
                let px = rowOffset + col * 4
                let blue = Float(buffer[px]), green = Float(buffer[px + 1]), red = Float(buffer[px + 2])
                total += (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255.0
                count += 1
            }
        }
        return count > 0 ? total / Float(count) : 0
    }
}
