//
//  CropConfiguration.swift
//  CropKit
//
//  Created by AnhPT on 03/07/2026.
//

import UIKit

/// Crop output shape.
public enum CropShape: Equatable {
    case rectangle
    case ellipse
    case roundedRect(cornerRadius: CGFloat)
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
public enum CropAspectRatio: Equatable {
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
    /// zooming the image so the cropped region is preserved (TOCrop-style).
    public var growsBackAfterResize: Bool

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
                growsBackAfterResize: Bool = true) {
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
    }
}
