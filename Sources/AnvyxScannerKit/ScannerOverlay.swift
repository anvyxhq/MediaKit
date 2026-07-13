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
    public var color: Color

    public init(quads: [DocumentQuad] = [], textLines: [TextLine] = [], color: Color = .yellow) {
        self.quads = quads
        self.textLines = textLines
        self.color = color
    }

    public var body: some View {
        Canvas { context, size in
            func map(_ point: CGPoint) -> CGPoint {
                CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
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
                let y = (1 - box.minY) * size.height   // baseline of the text line
                var underline = Path()
                underline.move(to: CGPoint(x: box.minX * size.width, y: y))
                underline.addLine(to: CGPoint(x: box.maxX * size.width, y: y))
                context.stroke(underline, with: .color(color), lineWidth: 2.5)
            }
        }
        .allowsHitTesting(false)
    }
}
