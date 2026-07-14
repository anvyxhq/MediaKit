//
//  RenderBufferPool.swift
//  ScannerKit
//
//  Created by AnhPT on 14/07/2026.
//

import CoreVideo
import Accelerate

/// A size-keyed `CVPixelBufferPool` for per-frame downscaling. Reusing pooled
/// buffers + vImage (instead of `CVPixelBufferCreate` + CoreImage every frame)
/// avoids the IOSurface/Metal churn that leaks memory in a live camera pipeline.
///
/// Not thread-safe by itself — create one per analysis loop (single serial
/// consumer), which is how ``LiveScanner`` uses it.
final class RenderBufferPool {
    private var pool: CVPixelBufferPool?
    private var width = 0
    private var height = 0

    /// A BGRA buffer of the given size, drawn from the pool (rebuilt if the size changed).
    func buffer(width: Int, height: Int) -> CVPixelBuffer? {
        guard width > 0, height > 0 else { return nil }
        if pool == nil || width != self.width || height != self.height {
            self.width = width
            self.height = height
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
            var created: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil,
                                    [kCVPixelBufferPoolMinimumBufferCountKey as String: 2] as CFDictionary,
                                    attributes as CFDictionary, &created)
            pool = created
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }

    /// Downscale a BGRA source frame into a pooled buffer (longest edge ≤ `maxDimension`)
    /// using vImage — no per-frame allocation or CoreImage render.
    func downscaled(_ source: CVPixelBuffer, maxDimension: CGFloat) -> CVPixelBuffer? {
        let sourceWidth = CVPixelBufferGetWidth(source)
        let sourceHeight = CVPixelBufferGetHeight(source)
        let longest = CGFloat(max(sourceWidth, sourceHeight))
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let targetWidth = max(1, Int((CGFloat(sourceWidth) * scale).rounded()))
        let targetHeight = max(1, Int((CGFloat(sourceHeight) * scale).rounded()))
        guard let destination = buffer(width: targetWidth, height: targetHeight) else { return nil }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(destination, [])
        }
        guard let sourceBase = CVPixelBufferGetBaseAddress(source),
              let destinationBase = CVPixelBufferGetBaseAddress(destination) else { return nil }

        var sourceBuffer = vImage_Buffer(data: sourceBase,
                                         height: vImagePixelCount(sourceHeight),
                                         width: vImagePixelCount(sourceWidth),
                                         rowBytes: CVPixelBufferGetBytesPerRow(source))
        var destinationBuffer = vImage_Buffer(data: destinationBase,
                                              height: vImagePixelCount(targetHeight),
                                              width: vImagePixelCount(targetWidth),
                                              rowBytes: CVPixelBufferGetBytesPerRow(destination))
        let error = vImageScale_ARGB8888(&sourceBuffer, &destinationBuffer, nil,
                                         vImage_Flags(kvImageHighQualityResampling))
        return error == kvImageNoError ? destination : nil
    }
}
