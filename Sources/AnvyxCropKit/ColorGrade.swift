//
//  ColorGrade.swift
//  CropKit
//
//  Created by AnhPT on 13/07/2026.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// A parametric color grade — a "look" defined by white-balance, saturation,
/// contrast, brightness, and vibrance. Compose your own or pick a
/// ``ColorGradePreset``. Complements the fixed `CIPhotoEffect` presets in
/// ``ColorFilter`` with an open, tweakable color-grading model.
public struct ColorGrade: Sendable, Equatable {
    /// Target neutral temperature in Kelvin (6500 = unchanged; lower = warmer).
    public var temperature: Double
    /// Green–magenta tint (0 = unchanged).
    public var tint: Double
    /// Saturation multiplier (1 = unchanged; 0 = grayscale).
    public var saturation: Double
    /// Contrast multiplier (1 = unchanged).
    public var contrast: Double
    /// Brightness offset (0 = unchanged).
    public var brightness: Double
    /// Vibrance amount (0 = unchanged; boosts muted colors, protects skin tones).
    public var vibrance: Double

    public init(
        temperature: Double = 6500,
        tint: Double = 0,
        saturation: Double = 1,
        contrast: Double = 1,
        brightness: Double = 0,
        vibrance: Double = 0
    ) {
        self.temperature = temperature
        self.tint = tint
        self.saturation = saturation
        self.contrast = contrast
        self.brightness = brightness
        self.vibrance = vibrance
    }

    /// `true` when every parameter is neutral (applying is a no-op).
    public var isNeutral: Bool {
        temperature == 6500 && tint == 0 && saturation == 1 && contrast == 1 && brightness == 0 && vibrance == 0
    }

    /// Apply the grade, returning a new `CGImage` (or the input unchanged when neutral).
    public func apply(to image: CGImage, context: CIContext = CIContext(options: nil)) -> CGImage {
        guard !isNeutral else { return image }
        var ciImage = CIImage(cgImage: image)

        if temperature != 6500 || tint != 0 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = ciImage
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: temperature, y: tint)
            ciImage = filter.outputImage ?? ciImage
        }
        if saturation != 1 || contrast != 1 || brightness != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = ciImage
            filter.saturation = Float(saturation)
            filter.contrast = Float(contrast)
            filter.brightness = Float(brightness)
            ciImage = filter.outputImage ?? ciImage
        }
        if vibrance != 0 {
            let filter = CIFilter.vibrance()
            filter.inputImage = ciImage
            filter.amount = Float(vibrance)
            ciImage = filter.outputImage ?? ciImage
        }
        return context.createCGImage(ciImage, from: ciImage.extent) ?? image
    }
}

/// A curated library of color-grade "looks" — a bigger, tweakable palette than the
/// stock `CIPhotoEffect`s.
public enum ColorGradePreset: String, CaseIterable, Sendable {
    case original, warm, cool, vivid, muted, vintage, cinematic
    case sunset, arctic, dramatic, filmNoir, cyberpunk, goldenHour

    public var grade: ColorGrade {
        switch self {
        case .original:   ColorGrade()
        case .warm:       ColorGrade(temperature: 5200, saturation: 1.06, vibrance: 0.10)
        case .cool:       ColorGrade(temperature: 8200, saturation: 1.00, vibrance: 0.05)
        case .vivid:      ColorGrade(saturation: 1.35, contrast: 1.10, vibrance: 0.30)
        case .muted:      ColorGrade(saturation: 0.72, contrast: 0.96)
        case .vintage:    ColorGrade(temperature: 5500, tint: 8, saturation: 0.80, contrast: 0.92, brightness: 0.03)
        case .cinematic:  ColorGrade(temperature: 5000, tint: -6, saturation: 1.10, contrast: 1.16)
        case .sunset:     ColorGrade(temperature: 4500, tint: 10, saturation: 1.20, vibrance: 0.15)
        case .arctic:     ColorGrade(temperature: 9000, tint: -8, saturation: 0.90, contrast: 1.05)
        case .dramatic:   ColorGrade(saturation: 1.10, contrast: 1.40, brightness: -0.02)
        case .filmNoir:   ColorGrade(saturation: 0, contrast: 1.35, brightness: -0.02)
        case .cyberpunk:  ColorGrade(temperature: 7000, tint: 22, saturation: 1.50, contrast: 1.20)
        case .goldenHour: ColorGrade(temperature: 4700, tint: 6, saturation: 1.15, brightness: 0.04, vibrance: 0.12)
        }
    }

    public var displayName: String {
        switch self {
        case .filmNoir:   "Film Noir"
        case .goldenHour: "Golden Hour"
        default:          rawValue.capitalized
        }
    }

    /// Apply this preset to an image.
    public func apply(to image: CGImage, context: CIContext = CIContext(options: nil)) -> CGImage {
        grade.apply(to: image, context: context)
    }
}
