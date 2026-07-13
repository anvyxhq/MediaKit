//
//  ScannerOverlay.swift
//  ScannerKit
//
//  Created by AnhPT on 13/07/2026.
//

import SwiftUI
import AnvyxCropKit

/// Draws detected document frames and/or text underlines over a camera preview.
/// Coordinates are Vision-normalized (bottom-left origin) and mapped to the
/// overlay's own size — size the overlay to match the preview.
public struct ScannerOverlay: View {
    public var quads: [DocumentQuad]
    public var textLines: [TextLine]
    /// Analyzed frame aspect (width / height) in display orientation, so detections
    /// map correctly onto the aspect-fill camera preview.
    public var contentAspect: CGFloat
    public var color: Color

    public init(quads: [DocumentQuad] = [], textLines: [TextLine] = [],
                contentAspect: CGFloat = 3.0 / 4.0, color: Color = .yellow) {
        self.quads = quads
        self.textLines = textLines
        self.contentAspect = contentAspect
        self.color = color
    }

    public var body: some View {
        let aspect = contentAspect
        Canvas { context, size in
            // Aspect-fill: the preview scales the frame to cover the view, cropping
            // the overflow — mirror that transform so overlays sit on the content.
            let viewAspect = size.width / size.height
            var displayW = size.width, displayH = size.height
            var offsetX: CGFloat = 0, offsetY: CGFloat = 0
            if viewAspect > aspect {
                displayH = size.width / aspect
                offsetY = (size.height - displayH) / 2
            } else {
                displayW = size.height * aspect
                offsetX = (size.width - displayW) / 2
            }
            func map(_ point: CGPoint) -> CGPoint {   // normalized bottom-left → view
                CGPoint(x: offsetX + point.x * displayW,
                        y: offsetY + (1 - point.y) * displayH)
            }

            for quad in quads {
                var path = Path()
                path.move(to: map(quad.topLeft))
                path.addLine(to: map(quad.topRight))
                path.addLine(to: map(quad.bottomRight))
                path.addLine(to: map(quad.bottomLeft))
                path.closeSubpath()
                context.fill(path, with: .color(color.opacity(0.15)))
                context.stroke(path, with: .color(color), lineWidth: 3)
            }

            for line in textLines {
                let box = line.boundingBox
                // The text baseline is the box's lower edge (minY in bottom-left space).
                var underline = Path()
                underline.move(to: map(CGPoint(x: box.minX, y: box.minY)))
                underline.addLine(to: map(CGPoint(x: box.maxX, y: box.minY)))
                context.stroke(underline, with: .color(color), lineWidth: 2.5)
            }
        }
        .allowsHitTesting(false)
    }
}
