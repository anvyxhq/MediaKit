//
//  CameraZoomLayout.swift
//  CameraKit
//
//  Created by AnhPT on 13/11/2026.
//

import AVFoundation

/// The zoom geometry of a capture device, and the math that maps a
/// *magnification* (1.0 = the field of view of the wide-angle lens) onto the
/// device's own `videoZoomFactor` scale.
///
/// On a virtual multi-lens device `videoZoomFactor` 1.0 is the *first*
/// constituent lens, which is the ultra-wide one when the device has it — so
/// the same factor frames differently from one device to the next. A
/// magnification always means the same thing: 1.0 is the wide lens, 2.0 is
/// twice as close.
///
/// The type is a plain value, so the math can be used (and tested) without
/// camera hardware:
///
/// ```swift
/// // Triple camera: ultra-wide → wide at 2.0, wide → telephoto at 6.0.
/// let layout = CameraZoomLayout(switchOverFactors: [2, 6], wideLensIndex: 1,
///                               minZoomFactor: 1, maxZoomFactor: 90)
/// layout.zoomFactor(forMagnification: 1)                        // 2.0
/// layout.zoomFactor(forMagnification: 5, stayOnWideLens: true)  // 5.94
/// ```
public struct CameraZoomLayout: Sendable, Equatable {

    /// How close to the next lens switch-over ``zoomFactor(forMagnification:stayOnWideLens:)``
    /// stops when asked to stay on the wide lens (a fraction of that factor).
    public static let switchOverMargin: CGFloat = 0.99

    /// The zoom factors at which a virtual device hands over to its next
    /// constituent lens, in lens order. Empty for a single physical lens.
    public var switchOverFactors: [CGFloat]

    /// Position of the wide-angle lens among the device's constituent lenses,
    /// or `nil` when the device is a single physical lens.
    public var wideLensIndex: Int?

    /// Lowest zoom factor the device accepts.
    public var minZoomFactor: CGFloat

    /// Highest zoom factor the device accepts with its active format.
    public var maxZoomFactor: CGFloat

    public init(
        switchOverFactors: [CGFloat] = [],
        wideLensIndex: Int? = nil,
        minZoomFactor: CGFloat = 1,
        maxZoomFactor: CGFloat = 1
    ) {
        self.switchOverFactors = switchOverFactors
        self.wideLensIndex = wideLensIndex
        self.minZoomFactor = minZoomFactor
        self.maxZoomFactor = maxZoomFactor
    }

    /// Read the layout from a device. The bounds follow the active format, so
    /// read it again after changing format or input.
    public init(device: AVCaptureDevice) {
        self.init(
            switchOverFactors: device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) },
            wideLensIndex: device.constituentDevices.firstIndex { $0.deviceType == .builtInWideAngleCamera },
            minZoomFactor: device.minAvailableVideoZoomFactor,
            maxZoomFactor: min(device.maxAvailableVideoZoomFactor, device.activeFormat.videoMaxZoomFactor)
        )
    }

    // MARK: - Lens boundaries

    /// The zoom factor at which the device frames through the wide-angle lens:
    /// 1.0 for a physical lens or a virtual device that starts with the wide
    /// lens, otherwise the switch-over factor that hands over to it.
    public var wideLensZoomFactor: CGFloat {
        guard let wideLensIndex, wideLensIndex > 0,
              switchOverFactors.indices.contains(wideLensIndex - 1) else { return 1 }
        let factor = switchOverFactors[wideLensIndex - 1]
        return factor.isFinite && factor > 0 ? factor : 1
    }

    /// The zoom factor at which the device leaves the wide lens for a longer
    /// one, or `nil` when there is no longer lens.
    public var nextLensZoomFactor: CGFloat? {
        guard let wideLensIndex, wideLensIndex >= 0,
              switchOverFactors.indices.contains(wideLensIndex) else { return nil }
        return switchOverFactors[wideLensIndex]
    }

    /// The range of magnifications the device can reach.
    public var magnificationRange: ClosedRange<CGFloat> {
        let lower = magnification(forZoomFactor: clampedZoomFactor(minZoomFactor))
        let upper = magnification(forZoomFactor: clampedZoomFactor(maxZoomFactor))
        return lower...max(lower, upper)
    }

    // MARK: - Conversion

    /// Convert a magnification into a zoom factor the device accepts.
    ///
    /// - Parameters:
    ///   - magnification: Zoom relative to the wide lens (1.0 = wide lens).
    ///   - stayOnWideLens: When `true`, the result is kept on the wide lens: not
    ///     below ``wideLensZoomFactor`` and just under ``nextLensZoomFactor``
    ///     (by ``switchOverMargin``), so the device never switches lens.
    /// - Returns: A factor inside `minZoomFactor...maxZoomFactor`. The device
    ///   limits win over the wide-lens limits when the two disagree.
    public func zoomFactor(forMagnification magnification: CGFloat, stayOnWideLens: Bool = false) -> CGFloat {
        var factor = wideLensZoomFactor * (magnification.isFinite ? magnification : 1)
        if stayOnWideLens {
            if let nextLensZoomFactor {
                factor = min(factor, nextLensZoomFactor * Self.switchOverMargin)
            }
            factor = max(factor, wideLensZoomFactor)
        }
        return clampedZoomFactor(factor)
    }

    /// Convert a device zoom factor into a magnification relative to the wide lens.
    public func magnification(forZoomFactor zoomFactor: CGFloat) -> CGFloat {
        zoomFactor / wideLensZoomFactor
    }

    /// Clamp a zoom factor to the range the device accepts. Setting a factor
    /// outside that range raises an exception in AVFoundation.
    public func clampedZoomFactor(_ zoomFactor: CGFloat) -> CGFloat {
        guard zoomFactor.isFinite, maxZoomFactor > minZoomFactor else { return minZoomFactor }
        return min(max(zoomFactor, minZoomFactor), maxZoomFactor)
    }
}
