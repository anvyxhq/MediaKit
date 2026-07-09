// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MediaKit",
    platforms: [
        .iOS("18.0")
    ],
    products: [
        .library(name: "AnvyxImageKit", targets: ["AnvyxImageKit"]),
        .library(name: "AnvyxCameraKit", targets: ["AnvyxCameraKit"]),
        .library(name: "AnvyxCropKit", targets: ["AnvyxCropKit"]),
        .library(name: "AnvyxStickerKit", targets: ["AnvyxStickerKit"]),
        .library(name: "AnvyxPDFKit", targets: ["AnvyxPDFKit"]),
    ],
    targets: [
        .target(name: "AnvyxImageKit"),
        .target(name: "AnvyxCameraKit"),
        .target(name: "AnvyxCropKit"),
        .target(name: "AnvyxStickerKit"),
        .target(name: "AnvyxPDFKit"),
        .testTarget(name: "AnvyxImageKitTests", dependencies: ["AnvyxImageKit"]),
        .testTarget(name: "AnvyxCameraKitTests", dependencies: ["AnvyxCameraKit"]),
        .testTarget(name: "AnvyxCropKitTests", dependencies: ["AnvyxCropKit"]),
        .testTarget(name: "AnvyxStickerKitTests", dependencies: ["AnvyxStickerKit"]),
        .testTarget(name: "AnvyxPDFKitTests", dependencies: ["AnvyxPDFKit"]),
    ]
)
