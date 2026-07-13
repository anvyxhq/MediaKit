//
//  ImageAdjust.swift
//  CropKit
//
//  Created by AnhPT on 03/07/2026.
//

import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal

/// Live color adjustments: brightness / contrast / saturation / exposure, plus
/// white balance (temperature / tint) and vibrance.
public struct ImageAdjustments: Equatable, Sendable {
    public var brightness: Float    // -1…1, 0 = none
    public var contrast: Float      //  0…2, 1 = none
    public var saturation: Float    //  0…2, 1 = none
    public var exposure: Float      // EV,  0 = none
    public var temperature: Float   // Kelvin, 6500 = none (lower = warmer)
    public var tint: Float          // green–magenta, 0 = none
    public var vibrance: Float      // -1…1, 0 = none

    public init(
        brightness: Float = 0,
        contrast: Float = 1,
        saturation: Float = 1,
        exposure: Float = 0,
        temperature: Float = 6500,
        tint: Float = 0,
        vibrance: Float = 0
    ) {
        self.brightness = brightness; self.contrast = contrast
        self.saturation = saturation; self.exposure = exposure
        self.temperature = temperature; self.tint = tint; self.vibrance = vibrance
    }
    public static let none = ImageAdjustments()
    public var isIdentity: Bool {
        brightness == 0 && contrast == 1 && saturation == 1 && exposure == 0
            && temperature == 6500 && tint == 0 && vibrance == 0
    }
}

/// Preset photo filters. `mono…process` are parameter-free `CIPhotoEffect`s
/// blended by intensity; `sepia`/`vignette` take a real intensity coefficient.
public enum ColorFilter: String, CaseIterable, Equatable, Sendable {
    case none, mono, noir, fade, chrome, instant, transfer, tonal, process, sepia, vignette

    var ciName: String? {
        switch self {
        case .none: return nil
        case .mono: return "CIPhotoEffectMono"
        case .noir: return "CIPhotoEffectNoir"
        case .fade: return "CIPhotoEffectFade"
        case .chrome: return "CIPhotoEffectChrome"
        case .instant: return "CIPhotoEffectInstant"
        case .transfer: return "CIPhotoEffectTransfer"
        case .tonal: return "CIPhotoEffectTonal"
        case .process: return "CIPhotoEffectProcess"
        case .sepia, .vignette: return nil   // handled with explicit intensity
        }
    }
    /// Whether this filter has its own intensity coefficient (vs. a blended preset).
    var isParametric: Bool { self == .sepia || self == .vignette }
    public var displayName: String { rawValue.capitalized }
}

enum CropCIContext {
    /// GPU-backed when a Metal device is available (much faster live filtering
    /// than the default CPU context), falling back to the default otherwise.
    static let shared: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device)
        }
        return CIContext(options: nil)
    }()
}

public extension ImageCropper {

    /// Apply color adjustments.
    static func adjusted(_ image: UIImage, _ adjustments: ImageAdjustments) -> UIImage {
        guard !adjustments.isIdentity, let input = CIImage(image: image) else { return image }
        var output = input
        let controls = CIFilter.colorControls()
        controls.inputImage = output
        controls.brightness = adjustments.brightness
        controls.contrast = adjustments.contrast
        controls.saturation = adjustments.saturation
        output = controls.outputImage ?? output
        if adjustments.exposure != 0 {
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = output
            exposure.ev = adjustments.exposure
            output = exposure.outputImage ?? output
        }
        if adjustments.temperature != 6500 || adjustments.tint != 0 {
            let whiteBalance = CIFilter.temperatureAndTint()
            whiteBalance.inputImage = output
            whiteBalance.neutral = CIVector(x: 6500, y: 0)
            whiteBalance.targetNeutral = CIVector(x: CGFloat(adjustments.temperature), y: CGFloat(adjustments.tint))
            output = whiteBalance.outputImage ?? output
        }
        if adjustments.vibrance != 0 {
            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = output
            vibrance.amount = adjustments.vibrance
            output = vibrance.outputImage ?? output
        }
        return render(output, like: image, extent: input.extent)
    }

    /// Apply a preset photo filter at `intensity` in `0…1`.
    static func filtered(_ image: UIImage, _ filter: ColorFilter, intensity: CGFloat = 1) -> UIImage {
        guard filter != .none, intensity > 0, let input = CIImage(image: image) else { return image }
        var output: CIImage?
        switch filter {
        case .sepia:
            let f = CIFilter.sepiaTone(); f.inputImage = input; f.intensity = Float(intensity); output = f.outputImage
        case .vignette:
            let f = CIFilter.vignette(); f.inputImage = input; f.intensity = Float(intensity * 2); f.radius = 2; output = f.outputImage
        default:
            guard let name = filter.ciName, let cif = CIFilter(name: name) else { return image }
            cif.setValue(input, forKey: kCIInputImageKey)
            output = cif.outputImage
        }
        guard var result = output else { return image }
        // Blend the preset look toward the original for a soft intensity.
        if intensity < 1, !filter.isParametric {
            result = result.applyingFilter("CIDissolveTransition", parameters: [
                "inputTargetImage": input, kCIInputTimeKey: 1 - intensity,
            ])
        }
        return render(result, like: image, extent: input.extent)
    }

    /// Apply an Instagram-style ``FilmPreset`` at `intensity` in `0…1` (with its color overlays).
    static func film(_ image: UIImage, _ preset: FilmPreset?, intensity: CGFloat = 1) -> UIImage {
        guard let preset, intensity > 0, let cg = image.cgImage else { return image }
        let out = preset.apply(to: cg, intensity: Float(intensity), context: CropCIContext.shared)
        return UIImage(cgImage: out, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Combined adjustments + filter + film preset in one render.
    static func process(_ image: UIImage, adjustments: ImageAdjustments,
                        filter: ColorFilter, filterIntensity: CGFloat = 1,
                        film preset: FilmPreset? = nil, filmIntensity: CGFloat = 1) -> UIImage {
        guard !adjustments.isIdentity || filter != .none || preset != nil else { return image }
        return film(filtered(adjusted(image, adjustments), filter, intensity: filterIntensity),
                    preset, intensity: filmIntensity)
    }

    private static func render(_ ciImage: CIImage, like image: UIImage, extent: CGRect) -> UIImage {
        guard let cg = CropCIContext.shared.createCGImage(ciImage, from: extent) else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: .up)
    }
}
