// swift-tools-version: 6.2
import PackageDescription

let concurrencyBaseline: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

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
        .target(name: "AnvyxImageKit", swiftSettings: concurrencyBaseline),
        .target(name: "AnvyxCameraKit", swiftSettings: concurrencyBaseline),
        .target(name: "AnvyxCropKit", swiftSettings: concurrencyBaseline),
        .testTarget(name: "AnvyxImageKitTests", dependencies: ["AnvyxImageKit"], swiftSettings: concurrencyBaseline),
        .testTarget(name: "AnvyxCameraKitTests", dependencies: ["AnvyxCameraKit"], swiftSettings: concurrencyBaseline),
        .testTarget(name: "AnvyxCropKitTests", dependencies: ["AnvyxCropKit"], swiftSettings: concurrencyBaseline),
    ]
)
