//
//  ImageKitTests.swift
//  ImageKit
//
//  Created by AnhPT on 03/07/2026.
//

import XCTest
@testable import AnvyxImageKit

final class ImageKitTests: XCTestCase {

    func testSolidColorImageHasRequestedSize() {
        let image = UIImage.solid(.red, size: CGSize(width: 4, height: 4))
        XCTAssertEqual(image.size, CGSize(width: 4, height: 4))
    }

    func testCropClampsToBounds() {
        let image = UIImage.solid(.green, size: CGSize(width: 10, height: 10))
        // Request a crop partly outside bounds; should clamp, not crash.
        let cropped = image.cropped(to: CGRect(x: 5, y: 5, width: 100, height: 100))
        XCTAssertNotNil(cropped)
    }

    func testRoundTripUIImageToPixelBufferAndBack() {
        // Render at scale 1 so point size == pixel size (device scale would make
        // the backing cgImage 2-3× larger than the 8×8 point size).
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        guard let buffer = image.toCVPixelBuffer() else {
            return XCTFail("expected a pixel buffer")
        }
        XCTAssertEqual(buffer.pixelWidth, 8)
        XCTAssertEqual(buffer.pixelHeight, 8)
        XCTAssertNotNil(buffer.toUIImage())
    }

    // MARK: - Async ImageProcessor

    /// A JPEG of `size` filled with `color`, for feeding the ImageIO paths.
    private func makeJPEGData(width: Int, height: Int, color: UIColor = .systemTeal) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 1.0)!
    }

    func testDownsampleCapsLongestEdge() async {
        let data = makeJPEGData(width: 2000, height: 1000)
        let cg = await ImageProcessor.downsample(data, maxPixelDimension: 256)
        guard let cg else { return XCTFail("expected a downsampled image") }
        XCTAssertEqual(max(cg.width, cg.height), 256)
        // Aspect ratio preserved (2:1 → 256×128).
        XCTAssertEqual(cg.width, 256)
        XCTAssertEqual(cg.height, 128)
    }

    func testDownsampleSmallerThanTargetIsNotUpscaled() async {
        let data = makeJPEGData(width: 100, height: 80)
        let cg = await ImageProcessor.downsample(data, maxPixelDimension: 512)
        guard let cg else { return XCTFail("expected an image") }
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 100)
    }

    func testDownsampledDataRoundTripsToSmallerImage() async {
        let data = makeJPEGData(width: 1600, height: 1600)
        let out = await ImageProcessor.downsampledData(data, maxPixelDimension: 200, format: .jpeg, quality: 0.7)
        guard let out else { return XCTFail("expected encoded data") }
        // Re-decode the produced data and confirm its dimensions were reduced.
        let decoded = await ImageProcessor.downsample(out, maxPixelDimension: 10_000)
        XCTAssertEqual(decoded.map { max($0.width, $0.height) }, 200)
    }

    func testEncodeProducesDecodableDataForEveryFormat() async {
        let data = makeJPEGData(width: 64, height: 64)
        guard let cg = await ImageProcessor.downsample(data, maxPixelDimension: 64) else {
            return XCTFail("expected a source image")
        }
        for format in [ImageFormat.jpeg, .png, .heic] {
            let encoded = await ImageProcessor.encodedData(cg, as: format, quality: 0.9)
            XCTAssertNotNil(encoded, "encoding \(format) should succeed")
            // The bytes must decode back to a real image of the same pixel size.
            let redecoded = await ImageProcessor.downsample(encoded ?? Data(), maxPixelDimension: 10_000)
            XCTAssertEqual(redecoded?.width, 64, "\(format) round-trip width")
            XCTAssertEqual(redecoded?.height, 64, "\(format) round-trip height")
        }
    }

    func testCropReturnsRequestedRegionAndClamps() async {
        let data = makeJPEGData(width: 100, height: 100)
        guard let cg = await ImageProcessor.downsample(data, maxPixelDimension: 100) else {
            return XCTFail("expected a source image")
        }
        let cropped = await ImageProcessor.crop(cg, to: CGRect(x: 10, y: 10, width: 40, height: 40))
        XCTAssertEqual(cropped?.width, 40)
        XCTAssertEqual(cropped?.height, 40)
        // Fully out-of-bounds crop returns nil rather than crashing.
        let none = await ImageProcessor.crop(cg, to: CGRect(x: 500, y: 500, width: 40, height: 40))
        XCTAssertNil(none)
    }

    // MARK: - Benchmark

    /// Downsampling a large image should be fast because ImageIO decodes at the
    /// target size instead of fully decoding first. Bridged into `measure` via a
    /// semaphore since the API is async.
    func testDownsamplePerformance() {
        let data = makeJPEGData(width: 4032, height: 3024) // ~12MP, typical camera frame
        measure {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                _ = await ImageProcessor.downsample(data, maxPixelDimension: 512)
                semaphore.signal()
            }
            semaphore.wait()
        }
    }
}
