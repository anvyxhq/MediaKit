//
//  CameraSourceValidation.swift
//  CameraKit
//
//  Created by AnhPT on 14/07/2026.
//

import AVFoundation

public extension AVCaptureDevice {
    /// `true` only for a genuine built-in camera — rejects Continuity Camera,
    /// external/USB, virtual, and unspecified-position devices. Useful when the
    /// authenticity of a scan/capture matters (e.g. eKYC-style flows).
    var isTrustedBuiltInCamera: Bool {
        guard position != .unspecified else { return false }
        if #available(iOS 17.0, *), deviceType == .external { return false }
        if #available(iOS 16.0, *), isContinuityCamera { return false }
        let trusted: Set<AVCaptureDevice.DeviceType> = [
            .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera,
            .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera, .builtInTrueDepthCamera,
        ]
        return trusted.contains(deviceType)
    }
}
