//
//  ScanGuidance.swift
//  ScannerKit
//
//  Created by AnhPT on 14/07/2026.
//

import CoreVideo
import CoreGraphics
import AnvyxCropKit

/// Live guidance for the user, computed each frame from brightness and framing —
/// show ``message`` as an on-screen hint (like a real document scanner).
public enum ScanGuidance: Sendable, Equatable {
    case searching
    case tooDark
    case tooBright
    case moveCloser
    case moveAway
    case holdSteady
    case ready

    public var message: String {
        switch self {
        case .searching:  "Point at a document"
        case .tooDark:    "Too dark — find better light"
        case .tooBright:  "Too bright — reduce glare"
        case .moveCloser: "Move closer"
        case .moveAway:   "Move away"
        case .holdSteady: "Hold steady"
        case .ready:      "Ready"
        }
    }
}

enum FrameQuality {
    /// Average scene brightness in `0…1`, sampled every `step` pixels of a BGRA buffer.
    static func averageBrightness(of pixelBuffer: CVPixelBuffer, step: Int = 24) -> CGFloat {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0.5 }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pointer = base.assumingMemoryBound(to: UInt8.self)

        var sum = 0.0, count = 0
        var y = 0
        while y < height {
            let row = y * bytesPerRow
            var x = 0
            while x < width {
                let i = row + x * 4                 // BGRA
                let b = Double(pointer[i]), g = Double(pointer[i + 1]), r = Double(pointer[i + 2])
                sum += 0.299 * r + 0.587 * g + 0.114 * b
                count += 1
                x += step
            }
            y += step
        }
        return count > 0 ? CGFloat(sum / Double(count) / 255.0) : 0.5
    }

    /// Normalized area (`0…1`) of a quad via the shoelace formula.
    static func area(of quad: DocumentQuad) -> CGFloat {
        let points = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
        var sum: CGFloat = 0
        for i in 0..<4 {
            let j = (i + 1) % 4
            sum += points[i].x * points[j].y - points[j].x * points[i].y
        }
        return abs(sum) / 2
    }
}
