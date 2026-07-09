//
//  UIImage+ImageKit.swift
//  ImageKit
//
//  Created by AnhPT on 03/07/2026.
//

import CoreImage
import CoreVideo
import UIKit

public extension UIImage {

    // MARK: - Construction

    /// Wrap a pixel buffer as a `CIImage`-backed `UIImage`.
    convenience init(pixelBuffer: CVPixelBuffer) {
        self.init(ciImage: CIImage(cvPixelBuffer: pixelBuffer))
    }

    /// A 1×1 image filled with `color` (useful for tinting backgrounds/buttons).
    static func solid(_ color: UIColor, size: CGSize = CGSize(width: 1, height: 1)) -> UIImage {
        let rect = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.cgContext.fill(rect)
        }
    }

    // MARK: - Conversion

    /// Render into a new `kCVPixelFormatType_32ARGB` buffer.
    func toCVPixelBuffer() -> CVPixelBuffer? {
        guard let cgImage else { return nil }
        let frame = CGSize(width: cgImage.width, height: cgImage.height)
        let options: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var out: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(frame.width), Int(frame.height),
                                         kCVPixelFormatType_32ARGB, options as CFDictionary, &out)
        guard status == kCVReturnSuccess, let buffer = out else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(frame.width), height: Int(frame.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(origin: .zero, size: frame))
        return buffer
    }

    // MARK: - Geometry

    /// A horizontally mirrored copy (preserving scale).
    func flippedHorizontally() -> UIImage? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: size.width, y: 0)
            cg.scaleBy(x: -1, y: 1)
            draw(at: .zero)
        }
    }

    /// Crop to `pixelRect` in pixel (CGImage) coordinates, clamped to bounds.
    func cropped(to pixelRect: CGRect) -> UIImage? {
        guard let cgImage else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let valid = pixelRect.intersection(bounds)
        guard !valid.isEmpty, let cropped = cgImage.cropping(to: valid) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }

    /// Center-crop to a 1:1 square.
    func croppedToSquare() -> UIImage {
        guard let cgImage else { return self }
        let side = min(cgImage.width, cgImage.height)
        let x = (cgImage.width - side) / 2
        let y = (cgImage.height - side) / 2
        guard let cropped = cgImage.cropping(to: CGRect(x: x, y: y, width: side, height: side)) else { return self }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }

    // MARK: - Storage / upload sizing

    /// Resize (longest side ≤ `maxDimension`) then JPEG-recompress to shrink the
    /// in-memory footprint — handy before persisting or uploading camera images.
    func optimizedForStorage(maxDimension: CGFloat = 1536, jpegQuality: CGFloat = 0.80) -> UIImage? {
        autoreleasepool {
            let resized = resized(maxDimension: maxDimension)
            guard let data = resized.jpegData(compressionQuality: jpegQuality) else { return resized }
            return UIImage(data: data)
        }
    }

    /// JPEG data whose size is kept at or below `maxMegabytes` by scaling quality.
    /// Dimensions are preserved.
    func limitedJPEGData(maxMegabytes: CGFloat = 1.0) -> Data? {
        let target = maxMegabytes * 1024 * 1024
        guard let full = jpegData(compressionQuality: 1.0) else { return nil }
        guard CGFloat(full.count) > target else { return full }
        let quality = min(max(target / CGFloat(full.count), 0.05), 1.0)
        return jpegData(compressionQuality: quality) ?? full
    }

    // MARK: - Private

    private func resized(maxDimension: CGFloat) -> UIImage {
        guard size.width > maxDimension || size.height > maxDimension else { return self }
        let scaleFactor = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: newSize))
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
