# ``AnvyxCropKit``

A full-featured image cropper (≥ Mantis): interactive crop with shapes & masks,
rotation dials, color adjustments & filters, undo/redo, and Vision document
edge-detection + perspective correction.

## Overview

Use the ready-made ``CropEditor`` SwiftUI screen, or compose ``CropperView`` /
``ImageCropperView`` with a ``CropController``. Auto-crop scanned documents with
``DocumentEdgeDetector`` + ``DocumentPerspective``.

```swift
CropEditor(image: photo, onDone: { cropped in … })

let quad = try await DocumentEdgeDetector().detectQuad(in: cg)   // iOS 26
let flat = quad.map { DocumentPerspective.corrected(cg, quad: $0) }
```

## Topics

### Cropping UI
- ``CropEditor``
- ``CropperView``
- ``ImageCropperView``
- ``CropController``
- ``RotationDial``
- ``RotationDialPlate``

### Core Operations
- ``ImageCropper``
- ``CropViewModel``

### State & Config
- ``CropState``
- ``CropInfo``
- ``CropDocument``
- ``CropConfiguration``
- ``CropShape``
- ``CropAspectRatio``
- ``ImageAdjustments``
- ``ColorFilter``

### Document Edges
- ``DocumentEdgeDetector``
- ``DocumentPerspective``
- ``DocumentQuad``
