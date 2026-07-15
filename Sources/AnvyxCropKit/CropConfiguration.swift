//
//  CropConfiguration.swift
//  CropKit
//
//  Created by AnhPT on 03/07/2026.
//

import UIKit

/// Crop output shape.
public enum CropShape: Equatable, Sendable {
    case rectangle
    case ellipse
    case roundedRect(cornerRadius: CGFloat)
    case diamond
    case heart
    /// A regular N-sided polygon inscribed in the crop box (`sides >= 3`).
    case polygon(sides: Int)
    /// An arbitrary closed shape, given as points normalized to `0...1` within the
    /// crop box (top-left origin).
    case path(points: [CGPoint])

    /// A bezier path for this shape inside `rect`. `cornerRadiusScale` scales the
    /// rounded-rect radius (used to convert point radii to pixels on export).
    func bezierPath(in rect: CGRect, cornerRadiusScale: CGFloat = 1) -> UIBezierPath {
        switch self {
        case .rectangle:
            return UIBezierPath(rect: rect)
        case .ellipse:
            return UIBezierPath(ovalIn: rect)
        case .roundedRect(let radius):
            return UIBezierPath(roundedRect: rect, cornerRadius: radius * cornerRadiusScale)
        case .diamond:
            return Self.polyline([
                CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY),
                CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY),
            ])
        case .heart:
            return Self.heartPath(in: rect)
        case .polygon(let sides):
            let n = max(3, sides)
            let cx = rect.midX, cy = rect.midY
            let rx = rect.width / 2, ry = rect.height / 2
            let points = (0..<n).map { i -> CGPoint in
                let a = -CGFloat.pi / 2 + 2 * .pi * CGFloat(i) / CGFloat(n)   // start at the top
                return CGPoint(x: cx + rx * cos(a), y: cy + ry * sin(a))
            }
            return Self.polyline(points)
        case .path(let points):
            let mapped = points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
            return Self.polyline(mapped)
        }
    }

    private static func polyline(_ points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.close()
        return path
    }

    /// A symmetric heart curve filling `rect`.
    private static func heartPath(in rect: CGRect) -> UIBezierPath {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        let path = UIBezierPath()
        let bottom = CGPoint(x: x + w / 2, y: y + h)
        path.move(to: bottom)
        path.addCurve(to: CGPoint(x: x, y: y + h / 4),
                      controlPoint1: CGPoint(x: x + w * 0.2, y: y + h * 0.75),
                      controlPoint2: CGPoint(x: x, y: y + h * 0.5))
        path.addArc(withCenter: CGPoint(x: x + w / 4, y: y + h / 4), radius: w / 4,
                    startAngle: .pi, endAngle: 0, clockwise: true)
        path.addArc(withCenter: CGPoint(x: x + w * 3 / 4, y: y + h / 4), radius: w / 4,
                    startAngle: .pi, endAngle: 0, clockwise: true)
        path.addCurve(to: bottom,
                      controlPoint1: CGPoint(x: x + w, y: y + h * 0.5),
                      controlPoint2: CGPoint(x: x + w * 0.8, y: y + h * 0.75))
        path.close()
        return path
    }
}

/// Style of the dimmed area outside the crop box.
public enum CropMaskStyle: Equatable {
    case dim
    case blur(UIBlurEffect.Style)
}

/// Which fine-rotation dial the ready-made editor shows.
public enum CropDialStyle: Equatable {
    case ruler   // horizontal ``RotationDialView``
    case plate   // circular ``RotationDialPlateView``
}

/// Crop-box aspect ratio.
public enum CropAspectRatio: Equatable, Sendable {
    case free
    case square
    /// A fixed width:height ratio.
    case ratio(CGFloat, CGFloat)
    /// A ratio that auto-swaps to match the image's orientation (e.g. 3:2 on a
    /// landscape photo becomes 2:3 on a portrait one).
    case oriented(CGFloat, CGFloat)

    /// Fixed width / height (landscape sense), or `nil` for free.
    public var value: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1
        case let .ratio(w, h): return h == 0 ? nil : w / h
        case let .oriented(w, h): return h == 0 ? nil : max(w, h) / min(w, h)
        }
    }

    /// Ratio resolved against an image size (handles `.oriented`).
    public func value(for imageSize: CGSize) -> CGFloat? {
        guard case let .oriented(w, h) = self, w > 0, h > 0 else { return value }
        let long = max(w, h), short = min(w, h)
        return imageSize.width >= imageSize.height ? long / short : short / long
    }

    /// A sensible default preset list for a ratio picker.
    public static let presets: [CropAspectRatio] = [
        .free, .square, .oriented(3, 2), .oriented(4, 3), .oriented(16, 9), .oriented(5, 4),
    ]

    public var label: String {
        switch self {
        case .free: return "Free"
        case .square: return "1:1"
        case let .ratio(w, h): return "\(Int(w)):\(Int(h))"
        case let .oriented(w, h): return "\(Int(max(w, h))):\(Int(min(w, h)))"
        }
    }
}

public struct CropConfiguration {
    public var aspectRatio: CropAspectRatio
    public var shape: CropShape
    public var maskStyle: CropMaskStyle
    public var showsGrid: Bool
    public var allowsRotation: Bool
    public var maskColor: UIColor
    public var maxZoom: CGFloat
    public var padding: CGFloat
    public var minimumBoxSize: CGFloat
    public var handleHotArea: CGFloat
    public var dialStyle: CropDialStyle
    /// After resizing the crop box, animate it back to fill the area while
    /// zooming the image so the cropped region is preserved.
    public var growsBackAfterResize: Bool
    /// Maximum absolute fine-rotation angle, in radians. The straighten dial and
    /// ``CropperView/rotationAngle`` are clamped to `±rotationLimit`. Defaults to
    /// `.pi` (the dial's full range — no practical limit, since image coverage now
    /// prevents empty corners at any angle). Set to `.pi / 4` for classic ±45°
    /// straighten behavior.
    public var rotationLimit: CGFloat
    /// When `true`, the crop box is fixed — the handles don't resize it and only
    /// the image can be panned/zoomed underneath.
    public var disableCropBoxDeformation: Bool
    /// When `true`, non-rectangular ``shape``s only clip the on-screen mask; the
    /// exported image stays rectangular.
    public var maskOnly: Bool

    public init(aspectRatio: CropAspectRatio = .free,
                shape: CropShape = .rectangle,
                maskStyle: CropMaskStyle = .dim,
                showsGrid: Bool = true,
                allowsRotation: Bool = true,
                maskColor: UIColor = UIColor.black.withAlphaComponent(0.55),
                maxZoom: CGFloat = 8,
                padding: CGFloat = 20,
                minimumBoxSize: CGFloat = 60,
                handleHotArea: CGFloat = 44,
                dialStyle: CropDialStyle = .ruler,
                growsBackAfterResize: Bool = true,
                rotationLimit: CGFloat = .pi,
                disableCropBoxDeformation: Bool = false,
                maskOnly: Bool = false) {
        self.aspectRatio = aspectRatio
        self.shape = shape
        self.maskStyle = maskStyle
        self.showsGrid = showsGrid
        self.allowsRotation = allowsRotation
        self.maskColor = maskColor
        self.maxZoom = maxZoom
        self.padding = padding
        self.minimumBoxSize = minimumBoxSize
        self.handleHotArea = handleHotArea
        self.dialStyle = dialStyle
        self.growsBackAfterResize = growsBackAfterResize
        self.rotationLimit = rotationLimit
        self.disableCropBoxDeformation = disableCropBoxDeformation
        self.maskOnly = maskOnly
    }
}
