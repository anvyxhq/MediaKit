//
//  ScannerOverlay.swift
//  ScannerKit
//
//  Created by AnhPT on 13/07/2026.
//

import SwiftUI
import AVFoundation
import AnvyxCropKit

/// Draws detected document frames and/or text underlines over a camera preview.
///
/// When a ``previewLayer`` is supplied, detections are mapped with
/// `AVCaptureVideoPreviewLayer.layerPointConverted(fromCaptureDevicePoint:)`,
/// which is exact across `videoGravity`, orientation, and mirroring (correct even
/// when the device rotates). Without a layer it falls back to aspect-fill math
/// using ``contentAspect``.
public struct ScannerOverlay: View {
    public var quads: [DocumentQuad]
    public var textLines: [TextLine]
    public var contentAspect: CGFloat
    public var previewLayer: AVCaptureVideoPreviewLayer?
    public var color: Color

    public init(quads: [DocumentQuad] = [], textLines: [TextLine] = [],
                contentAspect: CGFloat = 3.0 / 4.0,
                previewLayer: AVCaptureVideoPreviewLayer? = nil,
                color: Color = .yellow) {
        self.quads = quads
        self.textLines = textLines
        self.contentAspect = contentAspect
        self.previewLayer = previewLayer
        self.color = color
    }

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // Map on the main actor (layer access is main-only), then hand plain,
            // Sendable points to the Canvas renderer.
            let polygons: [[CGPoint]] = quads.map { quad in
                [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft].map { point($0, in: size) }
            }
            let underlines: [[CGPoint]] = textLines.map { line in
                [point(CGPoint(x: line.boundingBox.minX, y: line.boundingBox.minY), in: size),
                 point(CGPoint(x: line.boundingBox.maxX, y: line.boundingBox.minY), in: size)]
            }
            Canvas { context, _ in
                for polygon in polygons where polygon.count == 4 {
                    var path = Path()
                    path.move(to: polygon[0])
                    polygon.dropFirst().forEach { path.addLine(to: $0) }
                    path.closeSubpath()
                    context.fill(path, with: .color(color.opacity(0.15)))
                    context.stroke(path, with: .color(color), lineWidth: 3)
                }
                for underline in underlines where underline.count == 2 {
                    var path = Path()
                    path.move(to: underline[0])
                    path.addLine(to: underline[1])
                    context.stroke(path, with: .color(color), lineWidth: 2.5)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Vision-normalized point (bottom-left origin) → view point.
    private func point(_ p: CGPoint, in size: CGSize) -> CGPoint {
        if let layer = previewLayer {
            // Vision is bottom-left; capture-device (metadata) space is top-left.
            return layer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: p.x, y: 1 - p.y))
        }
        // Aspect-fill fallback: the preview covers the view, cropping overflow.
        let viewAspect = size.width / size.height
        var displayW = size.width, displayH = size.height
        var offsetX: CGFloat = 0, offsetY: CGFloat = 0
        if viewAspect > contentAspect {
            displayH = size.width / contentAspect
            offsetY = (size.height - displayH) / 2
        } else {
            displayW = size.height * contentAspect
            offsetX = (size.width - displayW) / 2
        }
        return CGPoint(x: offsetX + p.x * displayW, y: offsetY + (1 - p.y) * displayH)
    }
}
