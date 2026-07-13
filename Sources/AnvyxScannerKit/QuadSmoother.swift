//
//  QuadSmoother.swift
//  ScannerKit
//
//  Created by AnhPT on 13/07/2026.
//

import CoreGraphics
import AnvyxCropKit

/// Temporally smooths detected document quads so the on-screen frames don't
/// jitter frame-to-frame. Each new quad is matched to the nearest previous quad
/// (by centroid) and its corners are exponentially blended toward it; unmatched
/// quads appear immediately, and quads that vanish are dropped.
public struct QuadSmoother: Sendable {
    /// Blend weight toward the *previous* position, `0…1`. Higher = smoother but
    /// laggier. `0` disables smoothing.
    public var smoothing: CGFloat
    /// Max centroid distance (normalized) at which a new quad is considered the
    /// same document as a previous one.
    public var matchDistance: CGFloat

    private var previous: [DocumentQuad] = []

    public init(smoothing: CGFloat = 0.5, matchDistance: CGFloat = 0.12) {
        self.smoothing = max(0, min(1, smoothing))
        self.matchDistance = matchDistance
    }

    /// Feed the latest detections; returns the smoothed quads to display.
    public mutating func update(_ detected: [DocumentQuad]) -> [DocumentQuad] {
        guard smoothing > 0, !previous.isEmpty else {
            previous = detected
            return detected
        }
        let smoothed = detected.map { new -> DocumentQuad in
            guard let nearest = previous.min(by: {
                Self.centroidDistance($0, new) < Self.centroidDistance($1, new)
            }), Self.centroidDistance(nearest, new) <= matchDistance else {
                return new   // newly appeared — snap in
            }
            return Self.blend(previous: nearest, new: new, weight: smoothing)
        }
        previous = smoothed
        return smoothed
    }

    /// Forget history (call when scanning pauses / the mode changes).
    public mutating func reset() { previous = [] }

    // MARK: - Geometry

    static func centroid(_ quad: DocumentQuad) -> CGPoint {
        CGPoint(x: (quad.topLeft.x + quad.topRight.x + quad.bottomLeft.x + quad.bottomRight.x) / 4,
                y: (quad.topLeft.y + quad.topRight.y + quad.bottomLeft.y + quad.bottomRight.y) / 4)
    }

    static func centroidDistance(_ a: DocumentQuad, _ b: DocumentQuad) -> CGFloat {
        let p = centroid(a), q = centroid(b)
        return hypot(p.x - q.x, p.y - q.y)
    }

    static func blend(previous: DocumentQuad, new: DocumentQuad, weight t: CGFloat) -> DocumentQuad {
        func lerp(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x * t + b.x * (1 - t), y: a.y * t + b.y * (1 - t))
        }
        return DocumentQuad(
            topLeft: lerp(previous.topLeft, new.topLeft),
            topRight: lerp(previous.topRight, new.topRight),
            bottomLeft: lerp(previous.bottomLeft, new.bottomLeft),
            bottomRight: lerp(previous.bottomRight, new.bottomRight))
    }
}
