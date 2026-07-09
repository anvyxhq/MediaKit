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
    ],
    targets: [
        .target(name: "AnvyxImageKit"),
        .target(name: "AnvyxCameraKit"),
        .target(name: "AnvyxCropKit"),
        .testTarget(name: "AnvyxImageKitTests", dependencies: ["AnvyxImageKit"]),
        .testTarget(name: "AnvyxCameraKitTests", dependencies: ["AnvyxCameraKit"]),
        .testTarget(name: "AnvyxCropKitTests", dependencies: ["AnvyxCropKit"]),
    ]
)
