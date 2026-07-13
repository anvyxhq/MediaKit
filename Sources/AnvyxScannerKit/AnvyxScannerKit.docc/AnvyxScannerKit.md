# ``AnvyxScannerKit``

A live camera scanner: detect and frame one or more documents, or underline text
in real time, and capture perspective-corrected pages.

## Overview

`AnvyxScannerKit` is the **capture front-end** for scanning. It composes the
camera (``AnvyxCameraKit``) with on-device Vision detection and CropKit
perspective correction, and hands back `[UIImage]` pages — feed those to
`AnvyxDocProcessingKit` (in DocumentKit) to build a searchable PDF.

- **Document mode** — ``DocumentQuadDetector`` finds up to `maximumDocuments`
  rectangular documents per frame; ``ScannerOverlay`` draws a frame around each.
  The shutter perspective-corrects every detected document into an upright page.
- **Text mode** — ``TextLineDetector`` finds text lines; ``ScannerOverlay`` draws
  a live underline under each.

Drop in ``LiveScannerView`` for a ready-made screen, or drive ``LiveScanner``
yourself with your own UI.

```swift
LiveScannerView(mode: .document, maximumDocuments: 3) { pages in
    // pages: [UIImage] — perspective-corrected documents
} onCancel: { dismiss() }
```

Coordinates from the detectors are Vision-normalized (bottom-left origin, `0…1`),
matching CropKit's `DocumentQuad`.

## Topics

### Live scanning
- ``LiveScannerView``
- ``LiveScanner``
- ``ScannerOverlay``

### Detectors
- ``DocumentQuadDetector``
- ``TextLineDetector``
- ``TextLine``
