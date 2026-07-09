//
//  CIContext+Shared.swift
//  ImageKit
//
//  Created by AnhPT on 03/07/2026.
//

import CoreImage

/// A process-wide `CIContext`.
///
/// Building a `CIContext` per conversion is expensive — each spins up its own
/// Metal command queue and IOSurface-backed working textures. `CIContext` is
/// thread-safe, so ImageKit reuses one shared instance for all pixel-buffer /
/// image conversions.
enum SharedCIContext {
    static let context = CIContext(options: nil)
}
