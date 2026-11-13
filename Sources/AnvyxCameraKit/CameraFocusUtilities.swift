//
//  CameraFocusUtilities.swift
//  CameraKit
//
//  Created by AnhPT on 03/07/2026.
//

import AVFoundation

/// Low-level focus / exposure / white-balance primitives for `AVCaptureDevice`.
///
/// These are building blocks `CameraModel` doesn't expose directly — use them
/// when you need finer control (custom exposure bias, macro/low-light checks).
///
/// - Important: Every mutating call must run while the device's configuration
///   lock is held — AVFoundation raises otherwise. Use
///   `AVCaptureDevice.withConfigurationLock(_:)`, which does not run its body
///   when the lock cannot be taken. The capability checks (`wideAngleLens(of:)`,
///   `supportsMacroFocus`, `supportsLowLightBoost`) do not require the lock.
public enum CameraFocusUtilities {

    // MARK: - Focus mode

    public static func enableContinuousAutoFocus(for device: AVCaptureDevice) {
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
    }

    public static func enableAutoFocus(for device: AVCaptureDevice) {
        if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
    }

    public static func lockFocus(for device: AVCaptureDevice) {
        if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
    }

    // MARK: - Exposure

    public static func enableContinuousAutoExposure(for device: AVCaptureDevice) {
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
    }

    public static func enableAutoExposure(for device: AVCaptureDevice) {
        if device.isExposureModeSupported(.autoExpose) { device.exposureMode = .autoExpose }
    }

    /// Set exposure bias, clamped to the device's supported range.
    public static func setExposureBias(for device: AVCaptureDevice, bias: Float) {
        let clamped = min(max(device.minExposureTargetBias, bias), device.maxExposureTargetBias)
        device.setExposureTargetBias(clamped, completionHandler: nil)
    }

    // MARK: - Points of interest

    public static func setFocusPoint(for device: AVCaptureDevice, at point: CGPoint) {
        if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point }
    }

    public static func setExposurePoint(for device: AVCaptureDevice, at point: CGPoint) {
        if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = point }
    }

    /// Point focus and exposure at the frame center (0.5, 0.5).
    public static func setCenterPoints(for device: AVCaptureDevice) {
        let center = CGPoint(x: 0.5, y: 0.5)
        setFocusPoint(for: device, at: center)
        setExposurePoint(for: device, at: center)
    }

    // MARK: - White balance

    public static func enableContinuousAutoWhiteBalance(for device: AVCaptureDevice) {
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
    }

    public static func enableAutoWhiteBalance(for device: AVCaptureDevice) {
        if device.isWhiteBalanceModeSupported(.autoWhiteBalance) { device.whiteBalanceMode = .autoWhiteBalance }
    }

    // MARK: - Combined

    /// Enable continuous AF + AE + AWB, optionally applying an exposure bias.
    public static func enableContinuousModes(for device: AVCaptureDevice, exposureBias: Float = 0) {
        enableContinuousAutoFocus(for: device)
        enableContinuousAutoExposure(for: device)
        enableContinuousAutoWhiteBalance(for: device)
        if exposureBias != 0 { setExposureBias(for: device, bias: exposureBias) }
    }

    /// Continuous AF, optionally centered.
    public static func configureBasicFocus(for device: AVCaptureDevice, atCenter: Bool = true) {
        enableContinuousAutoFocus(for: device)
        if atCenter { setCenterPoints(for: device) }
    }

    // MARK: - Capability checks (no lock required)

    /// The wide-angle lens of `device`: the wide-angle constituent of a virtual
    /// multi-lens device, or the device itself when it is a single lens.
    ///
    /// Lens properties such as `minimumFocusDistance` describe whichever lens
    /// is active when read from a virtual device; read them from this lens to
    /// get a stable answer.
    public static func wideAngleLens(of device: AVCaptureDevice) -> AVCaptureDevice {
        device.constituentDevices.first { $0.deviceType == .builtInWideAngleCamera } ?? device
    }

    /// Whether the device is well suited to close-up / macro focus.
    ///
    /// The focus distance is read from the wide-angle lens (see
    /// ``wideAngleLens(of:)``), so the answer does not change with the lens a
    /// virtual device happens to be using.
    public static func supportsMacroFocus(_ device: AVCaptureDevice) -> Bool {
        let focusDistance = wideAngleLens(of: device).minimumFocusDistance
        if focusDistance > 0, focusDistance < 150 { return true } // < 15cm
        if device.deviceType == .builtInDualWideCamera {
            return device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
        }
        if device.deviceType == .builtInUltraWideCamera { return true }
        return device.isLockingFocusWithCustomLensPositionSupported
    }

    public static func supportsLowLightBoost(_ device: AVCaptureDevice) -> Bool {
        device.isLowLightBoostSupported
    }
}
