# ``AnvyxCameraKit``

A SwiftUI camera stack: an `@Observable` capture model, preview, hardware controls,
interruption handling, data/document scanning, and photo-library picking.

## Overview

``CameraModel`` (`@MainActor @Observable`) owns the `AVCaptureSession`; drop
``CameraView`` / ``CameraPreview`` in SwiftUI. Add barcode/text scanning with
``DataScannerView`` and document capture with ``DocumentScanner``.

```swift
@State private var camera = CameraModel()
CameraView(model: camera)
camera.enableHardwareCameraControls()   // iPhone 16 Camera Control
```

## Topics

### Capture
- ``CameraModel``
- ``CameraView``
- ``CameraPreview``
- ``CameraError``
- ``CameraOutputKind``

### Scanning
- ``DataScannerView``
- ``DocumentScanner``
- ``PhotoLibraryPicker``

### Device Info
- ``CameraDeviceDetector``
- ``CameraFocusUtilities``
- ``CameraZoomLayout``
