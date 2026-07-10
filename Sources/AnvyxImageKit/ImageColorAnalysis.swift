//
//  ImageColorAnalysis.swift
//  ImageKit
//
//  Created by AnhPT on 10/07/2026.
//

import CoreGraphics

/// An 8-bit-per-channel RGBA color — a `Sendable`, main-actor-free result type for
/// off-main image analysis (unlike `UIColor`, which is tied to UIKit).
public struct ImageColor: Sendable, Equatable, Hashable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// A `CGColor` in device RGB (safe to build off the main actor).
    public var cgColor: CGColor {
        CGColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255, alpha: CGFloat(alpha) / 255)
    }
}

public extension ImageProcessor {

    /// The single most prominent color in `image`. `nil` for an empty/fully
    /// transparent image.
    @concurrent
    static func dominantColor(_ image: sending CGImage, sampleSize: Int = 32) async -> ImageColor? {
        Self.colorHistogram(image, sampleSize: sampleSize).first
    }

    /// Up to `count` prominent colors, most-frequent first. Each is the average
    /// color of a quantized bucket, so near-identical shades collapse together.
    @concurrent
    static func palette(_ image: sending CGImage, count: Int = 5, sampleSize: Int = 32) async -> [ImageColor] {
        Array(Self.colorHistogram(image, sampleSize: sampleSize).prefix(max(0, count)))
    }

    // MARK: - Private

    /// Downscale into a small RGBA buffer, bucket colors by 4-bits-per-channel,
    /// and return each bucket's average color ordered by pixel count.
    private static func colorHistogram(_ image: CGImage, sampleSize: Int) -> [ImageColor] {
        let dim = max(1, sampleSize)
        let bytesPerRow = dim * 4
        var pixels = [UInt8](repeating: 0, count: dim * dim * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        struct Bucket { var count = 0; var r = 0; var g = 0; var b = 0 }
        var buckets: [UInt16: Bucket] = [:]

        pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(
                    data: base, width: dim, height: dim, bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow, space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }

            ctx.draw(image, in: CGRect(x: 0, y: 0, width: dim, height: dim))
            let ptr = base.assumingMemoryBound(to: UInt8.self)

            for i in stride(from: 0, to: dim * dim * 4, by: 4) {
                let alpha = ptr[i + 3]
                guard alpha >= 16 else { continue }   // ignore near-transparent
                let r = ptr[i], g = ptr[i + 1], b = ptr[i + 2]
                let key = (UInt16(r >> 4) << 8) | (UInt16(g >> 4) << 4) | UInt16(b >> 4)
                var bucket = buckets[key] ?? Bucket()
                bucket.count += 1
                bucket.r += Int(r); bucket.g += Int(g); bucket.b += Int(b)
                buckets[key] = bucket
            }
        }

        return buckets.values
            .sorted { $0.count > $1.count }
            .map { bucket in
                ImageColor(red: UInt8(bucket.r / bucket.count),
                           green: UInt8(bucket.g / bucket.count),
                           blue: UInt8(bucket.b / bucket.count))
            }
    }
}
