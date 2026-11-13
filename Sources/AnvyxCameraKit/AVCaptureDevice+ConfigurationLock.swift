//
//  AVCaptureDevice+ConfigurationLock.swift
//  CameraKit
//
//  Created by AnhPT on 13/11/2026.
//

import AVFoundation

extension AVCaptureDevice {
    /// Run `body` while holding the device's configuration lock.
    ///
    /// Changing a device property (zoom, focus, exposure, torch…) without the
    /// lock raises an exception. This takes the lock, runs `body`, and always
    /// releases the lock again. When the lock cannot be taken it throws and
    /// `body` does not run, so the device is never changed unlocked.
    ///
    /// ```swift
    /// try device.withConfigurationLock { device in
    ///     CameraFocusUtilities.enableContinuousModes(for: device)
    /// }
    /// ```
    ///
    /// - Parameter body: The changes to make; receives the locked device.
    /// - Returns: The value `body` returns.
    /// - Throws: The error from `lockForConfiguration()`, or the error `body` throws.
    @discardableResult
    public func withConfigurationLock<Result>(_ body: (AVCaptureDevice) throws -> Result) throws -> Result {
        try lockForConfiguration()
        defer { unlockForConfiguration() }
        return try body(self)
    }
}
