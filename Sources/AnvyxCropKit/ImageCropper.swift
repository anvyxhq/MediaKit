//
//  ImageCropper.swift
//  CropKit
//
//  Created by AnhPT on 03/07/2026.
//

import UIKit

/// The geometric description of a crop, in the cropper's *view-point* space.
///
/// - `translation`: crop-box center offset from the image-view center, measured
///   in the **unzoomed** image-view coordinate space (points).
/// - `rotation`: content rotation in radians (the angle the image was rotated on screen).
/// - `scale`: zoom factor (≥ 1 typically).
/// - `cropSize`: crop-box size on screen (points).
/// - `imageViewSize`: the image-view size at zoom 1 (aspect-fit).
public struct CropInfo: Equatable {
    public var translation: CGPoint
    public var rotation: CGFloat
    public var scale: CGFloat
    public var cropSize: CGSize
    public var imageViewSize: CGSize
    public var flipHorizontally: Bool
    public var flipVertically: Bool

    public init(translation: CGPoint = .zero, rotation: CGFloat = 0, scale: CGFloat = 1,
                cropSize: CGSize, imageViewSize: CGSize,
                flipHorizontally: Bool = false, flipVertically: Bool = false) {
        self.translation = translation; self.rotation = rotation; self.scale = scale
        self.cropSize = cropSize; self.imageViewSize = imageViewSize
        self.flipHorizontally = flipHorizontally; self.flipVertically = flipVertically
    }
}

/// Pure, UI-free cropping/rotation/flip operations.
public enum ImageCropper {

    /// Crop an axis-aligned rectangle given in **image-pixel** coordinates. Exact.
    public static func crop(_ image: UIImage, to pixelRect: CGRect) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let rect = pixelRect.integral.intersection(bounds)
        guard !rect.isEmpty, let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Rotate by a multiple of 90° (exact, lossless re-orientation).
    public static func rotated90(_ image: UIImage, quarterTurns: Int) -> UIImage? {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0, let cg = image.cgImage else { return image }
        let radians = CGFloat(turns) * .pi / 2
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let newSize = (turns % 2 == 0) ? CGSize(width: w, height: h) : CGSize(width: h, height: w)
        let renderer = UIGraphicsImageRenderer(size: newSize, format: opaqueFormat(image))
        return renderer.image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            c.rotate(by: radians)
            UIGraphicsPushContext(c)
            image.draw(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            UIGraphicsPopContext()
        }
    }

    /// Mirror horizontally and/or vertically (exact).
    public static func flipped(_ image: UIImage, horizontally: Bool, vertically: Bool) -> UIImage? {
        guard horizontally || vertically, let cg = image.cgImage else { return image }
        let size = CGSize(width: cg.width, height: cg.height)
        let renderer = UIGraphicsImageRenderer(size: size, format: opaqueFormat(image))
        return renderer.image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: size.width / 2, y: size.height / 2)
            c.scaleBy(x: horizontally ? -1 : 1, y: vertically ? -1 : 1)
            UIGraphicsPushContext(c)
            image.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
            UIGraphicsPopContext()
        }
    }

    /// General crop honoring pan / zoom / free rotation / flips.
    ///
    /// For `rotation == 0` and no flips this reduces to the exact ``crop(_:to:)``.
    /// Free-angle output uses the render path below and mirrors the on-screen transform.
    public static func crop(_ image: UIImage, by info: CropInfo) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let pixelScale = CGFloat(cg.width) / max(1, info.imageViewSize.width)   // image px per view point

        // Fast exact path: axis-aligned, unflipped.
        if info.rotation == 0, !info.flipHorizontally, !info.flipVertically {
            let regionW = info.cropSize.width / info.scale
            let regionH = info.cropSize.height / info.scale
            let centerX = info.imageViewSize.width / 2 + info.translation.x
            let centerY = info.imageViewSize.height / 2 + info.translation.y
            let rectPx = CGRect(x: (centerX - regionW / 2) * pixelScale,
                                y: (centerY - regionH / 2) * pixelScale,
                                width: regionW * pixelScale,
                                height: regionH * pixelScale)
            return crop(image, to: rectPx)
        }

        // General path: render the transformed image into the crop-box output.
        let outputSize = CGSize(width: info.cropSize.width / info.scale * pixelScale,
                                height: info.cropSize.height / info.scale * pixelScale)
        guard outputSize.width >= 1, outputSize.height >= 1 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: opaqueFormat(image))
        return renderer.image { rctx in
            let c = rctx.cgContext
            c.translateBy(x: outputSize.width / 2, y: outputSize.height / 2)
            c.scaleBy(x: info.flipHorizontally ? -1 : 1, y: info.flipVertically ? -1 : 1)
            c.rotate(by: -info.rotation)
            c.translateBy(x: -info.translation.x * pixelScale, y: -info.translation.y * pixelScale)
            let drawW = info.imageViewSize.width * pixelScale
            let drawH = info.imageViewSize.height * pixelScale
            UIGraphicsPushContext(c)
            image.draw(in: CGRect(x: -drawW / 2, y: -drawH / 2, width: drawW, height: drawH))
            UIGraphicsPopContext()
        }
    }

    /// Redraw the image with `.up` orientation so pixel-space crop rects match
    /// what the user sees (fixes camera photos with EXIF orientation).
    public static func normalizedUp(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size, format: opaqueFormat(image))
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    /// Clip a (already-cropped) image to a non-rectangular shape — transparent
    /// outside the shape. No-op for `.rectangle`.
    public static func masked(_ image: UIImage, shape: CropShape) -> UIImage {
        guard shape != .rectangle, let cg = image.cgImage else { return image }
        let size = CGSize(width: cg.width, height: cg.height)
        let renderer = UIGraphicsImageRenderer(size: size, format: opaqueFormat(image))
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let path: UIBezierPath
            switch shape {
            case .ellipse: path = UIBezierPath(ovalIn: rect)
            case .roundedRect(let radius): path = UIBezierPath(roundedRect: rect, cornerRadius: radius * image.scale)
            case .rectangle: path = UIBezierPath(rect: rect)
            }
            path.addClip()
            image.draw(in: rect)
        }
    }

    private static func opaqueFormat(_ image: UIImage) -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        return format
    }
}
