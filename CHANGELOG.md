# Changelog

All notable changes to this package are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Breaking

- **Breaking:** `CameraError` gained `.cannotAddOutput(_:)`; add it to exhaustive switches.
- **Breaking:** `start()` before `configure()` no longer starts an empty session.
- **Breaking:** `maxZoomFactor` reports the device limit instead of being capped at 10.
- **Breaking:** `focus(atViewPoint:)` returns to continuous focus and exposure after 3 seconds by default; pass `resetAfter: nil` to keep the old behaviour.

### Added

- Add single-document segmentation mode (iOS 26)
- Add AnvyxScannerKit — live document/text camera scanner
- Add Film strength slider to the adjust panel
- Add FilmPreset library (Instagram-style looks) + editor wiring
- Add temperature/tint/vibrance adjustments + ColorGrade intensity
- ColorGrade — parametric color-grade presets
- Cinematic Video, ProRAW, Constant Color, stabilization
- Document edge detection + perspective correction (line 105)
- Dominant color and palette extraction
- Hardware Camera Control support (Wave 2)
- AVCaptureSession interruption handling (Wave 2)
- Off-main async image processing (roadmap ImageKit P0·M)

### Changed

- Float the adjust panel over the cropper (no image resize on toggle)
- Rotation coverage, auto-detect/straighten, shapes, a11y
- Session-config / detector tests (P1)
- VImage + pooled buffers for per-frame downscale (#10)
- Finish eKYC learnings batch (#4/#5/#7/#8/#10/#15) + guard-let-self
- EKYC-inspired capture quality, guidance, perf metrics
- Toggleable auto-capture on document steadiness
- Batch perf/quality pass (pause, orientation, CIImage, adaptive, ROI...)
- Exact preview mapping + confidence hysteresis (anti-flicker)
- CPU/memory optimizations for live analysis
- Async frame pipeline + smoothing + accurate overlay mapping
- Keep crop box on tool switch + move dial degrees above the bar
- Speed up undo/redo & live editing
- Rotation dial rotates a full 360 with wrap-around
- Widen rotation dial range to +/-180 (free rotation)
- Migrate CropController/CropViewModel to @Observable
- Sendable for CropState and CropDocument value model
- Narrow MediaKit to Image/Camera/Crop (PDF+Sticker -> DocumentKit)
- Consolidated MediaKit (Anvyx* modules)

### Fixed

- Safe device configuration, session setup that reports failures, lens-aware zoom
- Fix runaway image growth on repeated rotate/flip (freeze)
- Fix slider lag + off-center rotation
