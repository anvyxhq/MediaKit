//
//  QuadTracker.swift
//  ScannerKit
//
//  Created by AnhPT on 13/07/2026.
//

import CoreGraphics
import AnvyxCropKit

/// A detected document quad with the detector's confidence.
public struct ScoredQuad: Sendable, Equatable {
    public var quad: DocumentQuad
    public var confidence: Float
    public init(quad: DocumentQuad, confidence: Float) {
        self.quad = quad
        self.confidence = confidence
    }
}

/// Stabilizes detected document frames across time to stop them flickering:
///
/// - **Confidence hysteresis** — a frame must reach `enterConfidence` to appear,
///   then stays visible until it drops below the lower `keepConfidence`.
/// - **Grace frames** — a frame that briefly vanishes is held for a few frames
///   instead of blinking out.
/// - **Smoothing** — matched corners are EMA-blended so the frame glides.
public struct QuadTracker: Sendable {
    public var enterConfidence: Float
    public var keepConfidence: Float
    public var graceFrames: Int
    public var smoothing: CGFloat
    public var matchDistance: CGFloat

    private struct Track {
        var quad: DocumentQuad
        var confidence: Float
        var missing: Int
        var visible: Bool
    }
    private var tracks: [Track] = []

    public init(enterConfidence: Float = 0.7,
                keepConfidence: Float = 0.4,
                graceFrames: Int = 6,
                smoothing: CGFloat = 0.5,
                matchDistance: CGFloat = 0.12) {
        self.enterConfidence = enterConfidence
        self.keepConfidence = keepConfidence
        self.graceFrames = graceFrames
        self.smoothing = smoothing
        self.matchDistance = matchDistance
    }

    /// Feed the latest scored detections; returns the visible, stabilized quads.
    public mutating func update(_ detections: [ScoredQuad]) -> [DocumentQuad] {
        var unmatched = Array(detections.indices)
        var next: [Track] = []

        // Carry forward existing tracks, matching each to the nearest detection.
        for var track in tracks {
            if let slot = unmatched.min(by: {
                QuadSmoother.centroidDistance(detections[$0].quad, track.quad)
                    < QuadSmoother.centroidDistance(detections[$1].quad, track.quad)
            }), QuadSmoother.centroidDistance(detections[slot].quad, track.quad) <= matchDistance {
                let detection = detections[slot]
                unmatched.removeAll { $0 == slot }
                track.quad = QuadSmoother.blend(previous: track.quad, new: detection.quad, weight: smoothing)
                track.confidence = detection.confidence
                track.missing = 0
                if detection.confidence >= enterConfidence { track.visible = true }
                else if detection.confidence < keepConfidence { track.visible = false }
                next.append(track)
            } else {
                track.missing += 1
                if track.missing <= graceFrames { next.append(track) }   // survive brief misses
            }
        }

        // Start tracks for detections that matched nothing.
        for slot in unmatched {
            let detection = detections[slot]
            next.append(Track(quad: detection.quad, confidence: detection.confidence,
                              missing: 0, visible: detection.confidence >= enterConfidence))
        }

        tracks = next
        return tracks.filter(\.visible).map(\.quad)
    }

    /// Forget all tracks (call when scanning pauses or the mode changes).
    public mutating func reset() { tracks = [] }
}
