//
//  CameraDeviceDetector.swift
//  CameraKit
//
//  Created by AnhPT on 03/07/2026.
//

import AVFoundation

/// The multi-lens camera system a device exposes as one logical back camera.
public enum CameraSystemType: Sendable {
    case single, dual, triple, unknown

    public var description: String {
        switch self {
        case .single:  return "Single Camera"
        case .dual:    return "Dual Camera"
        case .triple:  return "Triple Camera"
        case .unknown: return "Unknown Camera"
        }
    }
}

/// Stateless helper that discovers and selects the best capture device for a
/// position, going beyond a single `.builtInWideAngleCamera` to pick the
/// optimal multi-lens system when available.
///
/// `CameraModel` uses a simple default device; reach for this when you need
/// lens selection, a specific device type, or the device's system classification.
public struct CameraDeviceDetector {

    public struct DetectionResult {
        public let device: AVCaptureDevice?
        public let systemType: CameraSystemType
    }

    /// When `true`, prefer the plain wide-angle lens first (better for smooth
    /// pinch-zoom across the virtual zoom range); otherwise prefer the fused
    /// multi-lens system first (better default image quality).
    public var preferWideAngleForZoom: Bool

    public init(preferWideAngleForZoom: Bool = false) {
        self.preferWideAngleForZoom = preferWideAngleForZoom
    }

    // MARK: - Detection

    /// Pick the optimal device for `position`.
    public func detect(for position: AVCaptureDevice.Position) -> DetectionResult {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: Self.allDeviceTypes, mediaType: .video, position: position
        )
        let device = selectOptimalCamera(from: session.devices)
        let type = device.map { systemType(for: $0) } ?? CameraSystemType.unknown
        return DetectionResult(device: device, systemType: type)
    }

    /// Find a specific device type at `position`, if present.
    public func device(
        ofType deviceType: AVCaptureDevice.DeviceType,
        position: AVCaptureDevice.Position = .back
    ) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(deviceTypes: [deviceType], mediaType: .video, position: position)
            .devices.first
    }

    /// Classify the multi-lens system for `device` (front is always `.single`).
    public func systemType(for device: AVCaptureDevice) -> CameraSystemType {
        guard device.position != .front else { return .single }
        if Self.hasDevices([.builtInTripleCamera], at: .back) { return .triple }
        if Self.hasDevices([.builtInDualCamera, .builtInDualWideCamera], at: .back) { return .dual }
        return .single
    }

    // MARK: - Selection

    private func selectOptimalCamera(from devices: [AVCaptureDevice]) -> AVCaptureDevice? {
        guard !devices.isEmpty else { return nil }
        let priority = priorityOrder(for: devices)

        // Prefer higher-priority, functionally-verified devices; fall back to
        // priority order without the functionality probe; finally anything.
        for type in priority where devices.contains(where: { $0.deviceType == type }) {
            if let camera = devices.first(where: { $0.deviceType == type }), isFunctional(camera) {
                return camera
            }
        }
        for type in priority {
            if let camera = devices.first(where: { $0.deviceType == type }) { return camera }
        }
        return devices.first
    }

    private func priorityOrder(for devices: [AVCaptureDevice]) -> [AVCaptureDevice.DeviceType] {
        let hasTriple = devices.contains { $0.deviceType == .builtInTripleCamera }
        if !hasTriple { return Self.regularPriority }
        return preferWideAngleForZoom ? Self.proWideFirstPriority : Self.proFusedFirstPriority
    }

    /// Probe a device by briefly locking it — catches hardware that enumerates
    /// but fails to configure (constituent lenses on fused cameras included).
    private func isFunctional(_ device: AVCaptureDevice) -> Bool {
        let constituents = device.constituentDevices
        if device.deviceType == .builtInDualWideCamera || device.deviceType == .builtInTripleCamera {
            guard !constituents.isEmpty else { return false }
            for lens in constituents {
                guard (try? probe(lens)) != nil else { return false }
            }
        }
        return (try? probe(device)) != nil
    }

    private func probe(_ device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        _ = device.isFocusModeSupported(.continuousAutoFocus)
        _ = device.isExposureModeSupported(.continuousAutoExposure)
        device.unlockForConfiguration()
    }

    private static func hasDevices(_ types: [AVCaptureDevice.DeviceType], at position: AVCaptureDevice.Position) -> Bool {
        !AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: position).devices.isEmpty
    }

    // MARK: - Priority tables

    private static let allDeviceTypes: [AVCaptureDevice.DeviceType] = [
        .builtInTripleCamera, .builtInWideAngleCamera, .builtInDualCamera,
        .builtInDualWideCamera, .builtInUltraWideCamera, .builtInTelephotoCamera,
    ]
    private static let proFusedFirstPriority: [AVCaptureDevice.DeviceType] = [
        .builtInTripleCamera, .builtInDualCamera, .builtInWideAngleCamera,
        .builtInDualWideCamera, .builtInUltraWideCamera, .builtInTelephotoCamera,
    ]
    private static let proWideFirstPriority: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera, .builtInTripleCamera, .builtInDualWideCamera,
        .builtInDualCamera, .builtInUltraWideCamera, .builtInTelephotoCamera,
    ]
    private static let regularPriority: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera, .builtInDualCamera, .builtInUltraWideCamera,
        .builtInDualWideCamera, .builtInTelephotoCamera,
    ]
}
