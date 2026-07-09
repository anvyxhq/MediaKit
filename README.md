# MediaKit

> Camera capture, image processing, and cropping for modern SwiftUI apps.

![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)
![Platform](https://img.shields.io/badge/iOS-18%2B-000000?logo=apple)
![SPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen)
![License](https://img.shields.io/badge/License-MIT-blue)

MediaKit bundles three focused, dependency-free modules for working with photos and the camera. Each ships as its own library product, so you link only what you use.

## Features

- **Camera** — a complete SwiftUI camera (`CameraView`), an `@Observable` capture engine (`CameraModel`), native document scanning (`DocumentScanner`), live text/barcode scanning (`DataScannerView`), and a photo picker (`PhotoLibraryPicker`).
- **Cropping** — an end-to-end crop/rotate/flip editor with brightness/contrast/saturation adjustment, color filters, and undo/redo (`CropEditor`).
- **Imaging** — pixel-level utilities: `UIImage` ↔ `CVPixelBuffer`, storage-optimised encoding (`optimizedForStorage`, `limitedJPEGData`), and cropping.

No third-party dependencies — only AVFoundation, VisionKit, CoreImage, UIKit, and SwiftUI.

## Requirements

- iOS 18.0+
- Swift 5.9+ / Xcode 16+

## Installation

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/anvyxhq/MediaKit.git", branch: "main"),
```

Then add the products you need to your target: `AnvyxCameraKit`, `AnvyxCropKit`, `AnvyxImageKit`.

## Usage

```swift
import AnvyxCameraKit

struct ScanButton: View {
    var body: some View {
        CameraView { image in
            // handle the captured UIImage
        }
    }
}
```

```swift
import AnvyxCropKit

CropEditor(image: image) { result in
    // result is the cropped UIImage, or nil if cancelled
} onCancel: {
    // dismissed
}
```

```swift
import AnvyxImageKit

let data = image.optimizedForStorage(maxDimension: 2048, jpegQuality: 0.8)
```

## Modules

| Product | Description |
| --- | --- |
| `AnvyxImageKit` | `UIImage`/`CVPixelBuffer` conversion, resizing, storage-optimised encoding, cropping. |
| `AnvyxCameraKit` | SwiftUI camera, document scanner, live data scanner, photo-library picker. |
| `AnvyxCropKit` | Crop / rotate / flip editor with adjustments, color filters, and undo/redo. |

## License

MIT — see [LICENSE](LICENSE).
