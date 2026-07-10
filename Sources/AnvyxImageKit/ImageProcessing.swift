//
//  ImageProcessing.swift
//  ImageKit
//
//  Created by AnhPT on 10/07/2026.
//

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Encoded still-image container formats ImageKit can write.
public enum ImageFormat: Sendable {
    case jpeg
    case png
    case heic

    var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png:  return .png
        case .heic: return .heic
        }
    }
}

/// Off-main image processing built on ImageIO and CoreGraphics.
///
/// Every operation is `@concurrent` — it runs on the concurrent executor, never
/// the caller's actor — and works on `CGImage`/`Data` (not main-actor-bound
/// `UIImage`). Downsampling decodes at the target size via
/// `CGImageSourceCreateThumbnailAtIndex`, so peak memory stays proportional to
/// the *output*, not the (potentially huge) source image.
public enum ImageProcessor {

    // MARK: - Downsample (decode-at-size, low peak RAM)

    /// Downsample encoded image `data` so its longest edge is ≈ `maxPixelDimension`,
    /// applying the source's EXIF orientation. Returns `nil` if the data can't be decoded.
    @concurrent
    public static func downsample(_ data: Data, maxPixelDimension: Int) async -> sending CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        return Self.thumbnail(from: source, maxPixelDimension: maxPixelDimension)
    }

    /// Downsample the image at `url` without decoding it at full size first —
    /// the lowest-memory path, ideal for large files on disk.
    @concurrent
    public static func downsample(contentsOf url: URL, maxPixelDimension: Int) async -> sending CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        return Self.thumbnail(from: source, maxPixelDimension: maxPixelDimension)
    }

    /// Downsample encoded `data` and re-encode in one off-main step. Fully
    /// `Sendable` in and out — the common "shrink before upload/persist" path.
    @concurrent
    public static func downsampledData(
        _ data: Data,
        maxPixelDimension: Int,
        format: ImageFormat = .jpeg,
        quality: CGFloat = 0.8
    ) async -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let cgImage = Self.thumbnail(from: source, maxPixelDimension: maxPixelDimension) else { return nil }
        return Self.encode(cgImage, as: format, quality: quality)
    }

    // MARK: - Crop

    /// Crop `image` to `pixelRect` (in pixel coordinates), clamped to bounds.
    @concurrent
    public static func crop(_ image: sending CGImage, to pixelRect: CGRect) async -> sending CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let valid = pixelRect.intersection(bounds)
        guard !valid.isEmpty else { return nil }
        return image.cropping(to: valid)
    }

    // MARK: - Encode

    /// Encode `image` to `format` off-main. `quality` applies to lossy formats
    /// (JPEG/HEIC) and is ignored for PNG.
    @concurrent
    public static func encodedData(
        _ image: sending CGImage,
        as format: ImageFormat,
        quality: CGFloat = 0.9
    ) async -> Data? {
        Self.encode(image, as: format, quality: quality)
    }

    // MARK: - Private (synchronous cores, run on the concurrent executor)

    private static func thumbnail(from source: CGImageSource, maxPixelDimension: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelDimension),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encode(_ image: CGImage, as format: ImageFormat, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, format.utType.identifier as CFString, 1, nil
        ) else { return nil }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: min(max(quality, 0), 1)
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
