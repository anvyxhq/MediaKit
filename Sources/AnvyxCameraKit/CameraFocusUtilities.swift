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
/// - Important: Every mutating call must run inside a
///   `try device.lockForConfiguration()` / `device.unlockForConfiguration()`
///   block — AVFoundation raises otherwise. The capability checks
///   (`supportsMacroFocus`, `supportsLowLightBoost`) do not require the lock.
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

    /// Whether the device is well suited to close-up / macro focus.
    public static func supportsMacroFocus(_ device: AVCaptureDevice) -> Bool {
        if device.minimumFocusDistance > 0, device.minimumFocusDistance < 150 { return true } // < 15cm
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
