# ``AnvyxImageKit``

Off-main image processing on ImageIO / Core Graphics: memory-efficient downsampling,
cropping, encoding, and color analysis.

## Overview

``ImageProcessor`` runs every operation `@concurrent` (off the caller's actor) on
`CGImage`/`Data`, decoding at the target size so peak memory tracks the output, not
the source.

```swift
let thumb = await ImageProcessor.downsample(data, maxPixelDimension: 512)
let color = await ImageProcessor.dominantColor(cgImage)
```

## Topics

- ``ImageProcessor``
- ``ImageColor``
- ``ImageFormat``
