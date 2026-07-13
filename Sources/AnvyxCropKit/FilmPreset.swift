//
//  FilmPreset.swift
//  CropKit
//
//  Created by AnhPT on 13/07/2026.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// A filmic "look" recipe in the style of the classic Instagram filters, built
/// from a chain of Core Image primitives (sepia → hue → contrast/saturation →
/// brightness). Recipes are ported from the community `instagram.css` values.
///
/// Note on units: `contrast`, `saturation`, and `brightness` are **multipliers**
/// (`1` = unchanged), matching the CSS `filter` functions. `brightness` is a true
/// multiply (via `CIColorMatrix`), not the additive offset of `CIColorControls`.
public struct FilterRecipe: Sendable, Equatable {
    /// Sepia tone intensity (`0…1`, `0` = none).
    public var sepia: Float
    /// Contrast multiplier (`1` = none).
    public var contrast: Float
    /// Brightness multiplier (`1` = none).
    public var brightness: Float
    /// Saturation multiplier (`1` = none, `0` = grayscale).
    public var saturation: Float
    /// Hue rotation in degrees (`0` = none).
    public var hueDegrees: Float

    public init(
        sepia: Float = 0,
        contrast: Float = 1,
        brightness: Float = 1,
        saturation: Float = 1,
        hueDegrees: Float = 0
    ) {
        self.sepia = sepia
        self.contrast = contrast
        self.brightness = brightness
        self.saturation = saturation
        self.hueDegrees = hueDegrees
    }

    /// `true` when applying is a no-op.
    public var isNeutral: Bool {
        sepia == 0 && contrast == 1 && brightness == 1 && saturation == 1 && hueDegrees == 0
    }

    /// A copy interpolated toward neutral by `intensity` (clamped to `0…1`).
    public func scaled(by intensity: Float) -> FilterRecipe {
        let t = min(max(intensity, 0), 1)
        return FilterRecipe(
            sepia: sepia * t,
            contrast: 1 + (contrast - 1) * t,
            brightness: 1 + (brightness - 1) * t,
            saturation: 1 + (saturation - 1) * t,
            hueDegrees: hueDegrees * t
        )
    }

    /// Apply the recipe (plus any color `overlays`), returning a new `CGImage`
    /// (or the input unchanged when there is nothing to do).
    public func apply(to image: CGImage, overlays: [FilterOverlay] = [],
                      context: CIContext = CIContext(options: nil)) -> CGImage {
        guard !isNeutral || !overlays.isEmpty else { return image }
        var ciImage = CIImage(cgImage: image)

        if sepia > 0 {
            let filter = CIFilter.sepiaTone()
            filter.inputImage = ciImage
            filter.intensity = sepia
            ciImage = filter.outputImage ?? ciImage
        }
        if hueDegrees != 0 {
            let filter = CIFilter.hueAdjust()
            filter.inputImage = ciImage
            filter.angle = hueDegrees * .pi / 180
            ciImage = filter.outputImage ?? ciImage
        }
        if contrast != 1 || saturation != 1 {
            let filter = CIFilter.colorControls()
            filter.inputImage = ciImage
            filter.contrast = contrast
            filter.saturation = saturation
            ciImage = filter.outputImage ?? ciImage
        }
        if brightness != 1 {
            // Multiplicative brightness (CSS-style) — CIColorControls.brightness is an
            // additive offset, so scale RGB directly with a color matrix instead.
            let filter = CIFilter.colorMatrix()
            filter.inputImage = ciImage
            filter.rVector = CIVector(x: CGFloat(brightness), y: 0, z: 0, w: 0)
            filter.gVector = CIVector(x: 0, y: CGFloat(brightness), z: 0, w: 0)
            filter.bVector = CIVector(x: 0, y: 0, z: CGFloat(brightness), w: 0)
            ciImage = filter.outputImage ?? ciImage
        }
        let extent = ciImage.extent
        for overlay in overlays {
            ciImage = overlay.composited(over: ciImage, extent: extent)
        }
        return context.createCGImage(ciImage, from: extent) ?? image
    }

    /// Apply the recipe at `intensity` (`0…1`) — dial the look up or down.
    /// Overlays are not scaled; pass them only when you want the full look.
    public func apply(to image: CGImage, intensity: Float, overlays: [FilterOverlay] = [],
                      context: CIContext = CIContext(options: nil)) -> CGImage {
        scaled(by: intensity).apply(to: image, overlays: overlays, context: context)
    }
}

/// An RGBA color in the `0…1` range, used to describe filter overlays without
/// pulling in a CSS color parser.
public struct RGBA: Sendable, Equatable {
    public var red, green, blue, alpha: CGFloat
    public init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    /// From 8-bit `0…255` components (matches the CSS source values).
    public static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> RGBA {
        RGBA(r / 255, g / 255, b / 255, a)
    }
    public static let clear = RGBA(0, 0, 0, 0)
    public func opacity(_ scale: CGFloat) -> RGBA { RGBA(red, green, blue, alpha * scale) }
    public var ciColor: CIColor { CIColor(red: red, green: green, blue: blue, alpha: alpha) }
}

/// A color overlay layered on top of a filtered image, mirroring the CSS blend
/// overlays used by the CSSgram looks. Prettier than the plain recipe, but each
/// overlay adds a generator + blend pass.
public struct FilterOverlay: Sendable, Equatable {
    /// How the overlay layer is filled.
    public enum Fill: Sendable, Equatable {
        case solid(RGBA)
        /// A two-stop gradient. `vertical` runs top→bottom, else left→right.
        case linear(RGBA, RGBA, vertical: Bool)
        /// A centered two-stop radial gradient (inner → outer).
        case radial(RGBA, RGBA)
    }
    /// The Porter-Duff / separable blend mode, matching CSS `mix-blend-mode`.
    public enum Blend: String, Sendable, Equatable {
        case screen, multiply, overlay, darken, lighten
        case softLight, hardLight, colorBurn, colorDodge, exclusion, color

        var filterName: String {
            switch self {
            case .screen:     "CIScreenBlendMode"
            case .multiply:   "CIMultiplyBlendMode"
            case .overlay:    "CIOverlayBlendMode"
            case .darken:     "CIDarkenBlendMode"
            case .lighten:    "CILightenBlendMode"
            case .softLight:  "CISoftLightBlendMode"
            case .hardLight:  "CIHardLightBlendMode"
            case .colorBurn:  "CIColorBurnBlendMode"
            case .colorDodge: "CIColorDodgeBlendMode"
            case .exclusion:  "CIExclusionBlendMode"
            case .color:      "CIColorBlendMode"
            }
        }
    }

    public var fill: Fill
    public var blend: Blend
    public var opacity: CGFloat

    public init(fill: Fill, blend: Blend, opacity: CGFloat = 1) {
        self.fill = fill; self.blend = blend; self.opacity = opacity
    }

    private func layer(extent: CGRect) -> CIImage {
        switch fill {
        case .solid(let color):
            return CIImage(color: color.opacity(opacity).ciColor).cropped(to: extent)
        case .linear(let start, let end, let vertical):
            let gradient = CIFilter.linearGradient()
            gradient.color0 = start.opacity(opacity).ciColor
            gradient.color1 = end.opacity(opacity).ciColor
            // CI origin is bottom-left, so "top" is maxY.
            gradient.point0 = vertical ? CGPoint(x: extent.midX, y: extent.maxY)
                                       : CGPoint(x: extent.minX, y: extent.midY)
            gradient.point1 = vertical ? CGPoint(x: extent.midX, y: extent.minY)
                                       : CGPoint(x: extent.maxX, y: extent.midY)
            return (gradient.outputImage ?? .empty()).cropped(to: extent)
        case .radial(let inner, let outer):
            let gradient = CIFilter.radialGradient()
            gradient.center = CGPoint(x: extent.midX, y: extent.midY)
            gradient.radius0 = 0
            gradient.radius1 = Float(max(extent.width, extent.height) * 0.75)
            gradient.color0 = inner.opacity(opacity).ciColor
            gradient.color1 = outer.opacity(opacity).ciColor
            return (gradient.outputImage ?? .empty()).cropped(to: extent)
        }
    }

    /// Blend this overlay over `base`, clamped to `extent`.
    func composited(over base: CIImage, extent: CGRect) -> CIImage {
        guard let blender = CIFilter(name: blend.filterName) else { return base }
        blender.setValue(layer(extent: extent), forKey: kCIInputImageKey)
        blender.setValue(base, forKey: kCIInputBackgroundImageKey)
        return (blender.outputImage ?? base).cropped(to: extent)
    }
}

/// The classic Instagram-style film looks, ported from `instagram.css`.
/// Complements the `CIPhotoEffect`-based ``ColorFilter`` and the parametric
/// white-balance ``ColorGradePreset`` with a large, familiar preset library.
public enum FilmPreset: String, CaseIterable, Sendable {
    case _1977, aden, amaro, ashby, brannan, brooklyn, charmes, clarendon, crema
    case dogpatch, earlybird, gingham, ginza, hefe, helena, hudson, inkwell, juno
    case kelvin, lark, lofi, ludwig, maven, mayfair, moon, nashville, perpetua
    case poprocket, reyes, rise, sierra, skyline, slumber, stinson, sutro, toaster
    case valencia, vesper, walden, willow, xpro2

    public var recipe: FilterRecipe {
        switch self {
        case ._1977:     FilterRecipe(sepia: 0.5,  saturation: 1.4, hueDegrees: -30)
        case .aden:      FilterRecipe(sepia: 0.2,  brightness: 1.15, saturation: 1.4)
        case .amaro:     FilterRecipe(sepia: 0.35, contrast: 1.1,  brightness: 1.2,  saturation: 1.3)
        case .ashby:     FilterRecipe(sepia: 0.5,  contrast: 1.2,  saturation: 1.8)
        case .brannan:   FilterRecipe(sepia: 0.4,  contrast: 1.25, brightness: 1.1,  saturation: 0.9,  hueDegrees: -2)
        case .brooklyn:  FilterRecipe(sepia: 0.25, contrast: 1.25, brightness: 1.25, hueDegrees: 5)
        case .charmes:   FilterRecipe(sepia: 0.25, contrast: 1.25, brightness: 1.25, saturation: 1.35, hueDegrees: -5)
        case .clarendon: FilterRecipe(sepia: 0.15, contrast: 1.25, brightness: 1.25, hueDegrees: 5)
        case .crema:     FilterRecipe(sepia: 0.5,  contrast: 1.25, brightness: 1.15, saturation: 0.9,  hueDegrees: -2)
        case .dogpatch:  FilterRecipe(sepia: 0.35, contrast: 1.5,  saturation: 1.1)
        case .earlybird: FilterRecipe(sepia: 0.25, contrast: 1.25, brightness: 1.15, saturation: 0.9,  hueDegrees: -5)
        case .gingham:   FilterRecipe(contrast: 1.1,  brightness: 1.1)
        case .ginza:     FilterRecipe(sepia: 0.25, contrast: 1.15, brightness: 1.2,  saturation: 1.35, hueDegrees: -5)
        case .hefe:      FilterRecipe(sepia: 0.4,  contrast: 1.5,  brightness: 1.2,  saturation: 1.4,  hueDegrees: -10)
        case .helena:    FilterRecipe(sepia: 0.5,  contrast: 1.05, brightness: 1.05, saturation: 1.35)
        case .hudson:    FilterRecipe(sepia: 0.25, contrast: 1.2,  brightness: 1.2,  saturation: 1.05, hueDegrees: -15)
        case .inkwell:   FilterRecipe(contrast: 0.85, brightness: 1.25, saturation: 0)
        case .juno:      FilterRecipe(sepia: 0.35, contrast: 1.15, brightness: 1.15, saturation: 1.8)
        case .kelvin:    FilterRecipe(sepia: 0.15, contrast: 1.5,  brightness: 1.1,  hueDegrees: -10)
        case .lark:      FilterRecipe(sepia: 0.25, contrast: 1.2,  brightness: 1.3,  saturation: 1.25)
        case .lofi:      FilterRecipe(contrast: 1.5,  saturation: 1.1)
        case .ludwig:    FilterRecipe(sepia: 0.25, contrast: 1.05, brightness: 1.05, saturation: 2.0)
        case .maven:     FilterRecipe(sepia: 0.35, contrast: 1.05, brightness: 1.05, saturation: 1.75)
        case .mayfair:   FilterRecipe(contrast: 1.1,  brightness: 1.15, saturation: 1.1)
        case .moon:      FilterRecipe(sepia: 0.35, contrast: 0.95, brightness: 1.4,  saturation: 0)
        case .nashville: FilterRecipe(sepia: 0.25, contrast: 1.5,  brightness: 0.9,  hueDegrees: -15)
        case .perpetua:  FilterRecipe(contrast: 1.1,  brightness: 1.25, saturation: 1.1)
        case .poprocket: FilterRecipe(sepia: 0.15, brightness: 1.2)
        case .reyes:     FilterRecipe(sepia: 0.75, contrast: 0.75, brightness: 1.25, saturation: 1.4)
        case .rise:      FilterRecipe(sepia: 0.25, contrast: 1.25, brightness: 1.2,  saturation: 0.9)
        case .sierra:    FilterRecipe(sepia: 0.25, contrast: 1.5,  brightness: 0.9,  hueDegrees: -15)
        case .skyline:   FilterRecipe(sepia: 0.15, contrast: 1.25, brightness: 1.25, saturation: 1.2)
        case .slumber:   FilterRecipe(sepia: 0.35, contrast: 1.25, saturation: 1.25)
        case .stinson:   FilterRecipe(sepia: 0.35, contrast: 1.25, brightness: 1.1,  saturation: 1.25)
        case .sutro:     FilterRecipe(sepia: 0.4,  contrast: 1.2,  brightness: 0.9,  saturation: 1.4,  hueDegrees: -10)
        case .toaster:   FilterRecipe(sepia: 0.25, contrast: 1.5,  brightness: 0.95, hueDegrees: -15)
        case .valencia:  FilterRecipe(sepia: 0.25, contrast: 1.1,  brightness: 1.1)
        case .vesper:    FilterRecipe(sepia: 0.35, contrast: 1.15, brightness: 1.2,  saturation: 1.3)
        case .walden:    FilterRecipe(sepia: 0.35, contrast: 0.8,  brightness: 1.25, saturation: 1.4)
        case .willow:    FilterRecipe(sepia: 0.2,  contrast: 0.85, brightness: 1.2,  saturation: 0.05)
        case .xpro2:     FilterRecipe(sepia: 0.45, contrast: 1.25, brightness: 1.75, saturation: 1.3,  hueDegrees: -5)
        }
    }

    /// Color overlays layered on top of the base ``recipe`` for a richer, CSSgram-style
    /// look. Empty for presets that have no overlay in the source library.
    public var overlays: [FilterOverlay] {
        switch self {
        case ._1977:     [.init(fill: .solid(.rgb(243, 106, 188, 0.3)), blend: .screen)]
        case .aden:      [.init(fill: .linear(.rgb(66, 10, 14, 0.2), .clear, vertical: false), blend: .darken)]
        case .brannan:   [.init(fill: .solid(.rgb(161, 44, 199, 0.31)), blend: .lighten)]
        case .brooklyn:  [.init(fill: .radial(.rgb(168, 223, 193, 0.4), .rgb(196, 183, 200)), blend: .overlay)]
        case .clarendon: [.init(fill: .solid(.rgb(127, 187, 227, 0.2)), blend: .overlay)]
        case .earlybird: [.init(fill: .radial(.rgb(208, 186, 142), .rgb(29, 2, 16)), blend: .overlay)]
        case .gingham:   [.init(fill: .solid(.rgb(230, 230, 250)), blend: .softLight)]
        case .hudson:    [.init(fill: .radial(.rgb(166, 177, 255), .rgb(52, 33, 52)), blend: .multiply, opacity: 0.5)]
        case .kelvin:    [.init(fill: .solid(.rgb(56, 44, 52)), blend: .colorDodge),
                          .init(fill: .solid(.rgb(183, 125, 33)), blend: .overlay)]
        case .lark:      [.init(fill: .solid(.rgb(34, 37, 63)), blend: .colorDodge),
                          .init(fill: .solid(.rgb(242, 242, 242, 0.8)), blend: .darken)]
        case .lofi:      [.init(fill: .radial(.clear, .rgb(34, 34, 34)), blend: .multiply)]
        case .mayfair:   [.init(fill: .radial(.rgb(255, 255, 255, 0.8), .rgb(17, 17, 17)), blend: .overlay, opacity: 0.4)]
        case .moon:      [.init(fill: .solid(.rgb(160, 160, 160)), blend: .softLight),
                          .init(fill: .solid(.rgb(56, 56, 56)), blend: .lighten)]
        case .nashville: [.init(fill: .solid(.rgb(247, 176, 153, 0.56)), blend: .darken),
                          .init(fill: .solid(.rgb(0, 70, 150, 0.4)), blend: .lighten)]
        case .perpetua:  [.init(fill: .linear(.rgb(0, 91, 154), .rgb(230, 193, 61), vertical: true), blend: .softLight, opacity: 0.5)]
        case .reyes:     [.init(fill: .solid(.rgb(239, 205, 173)), blend: .softLight, opacity: 0.5)]
        case .rise:      [.init(fill: .radial(.rgb(236, 205, 169, 0.15), .rgb(50, 30, 7, 0.4)), blend: .multiply),
                          .init(fill: .radial(.rgb(232, 197, 152, 0.8), .clear), blend: .overlay, opacity: 0.6)]
        case .slumber:   [.init(fill: .solid(.rgb(69, 41, 12, 0.4)), blend: .lighten),
                          .init(fill: .solid(.rgb(125, 105, 24, 0.5)), blend: .softLight)]
        case .stinson:   [.init(fill: .solid(.rgb(240, 149, 128, 0.2)), blend: .softLight)]
        case .toaster:   [.init(fill: .radial(.rgb(128, 78, 15), .rgb(59, 0, 59)), blend: .screen)]
        case .valencia:  [.init(fill: .solid(.rgb(58, 3, 57)), blend: .exclusion, opacity: 0.5)]
        case .walden:    [.init(fill: .solid(.rgb(0, 68, 204)), blend: .screen, opacity: 0.3)]
        case .willow:    [.init(fill: .radial(.rgb(212, 169, 175), .rgb(0, 0, 0)), blend: .overlay),
                          .init(fill: .solid(.rgb(216, 205, 203)), blend: .color)]
        case .xpro2:     [.init(fill: .radial(.rgb(230, 231, 224), .rgb(43, 42, 161, 0.6)), blend: .colorBurn)]
        default:         []
        }
    }

    public var displayName: String {
        switch self {
        case ._1977:     "1977"
        case .earlybird: "Earlybird"
        case .poprocket: "Poprocket"
        case .xpro2:     "X-Pro II"
        default:         rawValue.capitalized
        }
    }

    /// Apply this preset — including its color ``overlays`` for the full CSSgram-style
    /// look. Use ``recipe`` directly (`preset.recipe.apply(to:)`) for the lighter,
    /// overlay-free version.
    public func apply(to image: CGImage, context: CIContext = CIContext(options: nil)) -> CGImage {
        recipe.apply(to: image, overlays: overlays, context: context)
    }

    /// Apply this preset at `intensity` (`0…1`); the base recipe is dialed, overlays
    /// are included at full strength.
    public func apply(to image: CGImage, intensity: Float, context: CIContext = CIContext(options: nil)) -> CGImage {
        recipe.apply(to: image, intensity: intensity, overlays: overlays, context: context)
    }
}
