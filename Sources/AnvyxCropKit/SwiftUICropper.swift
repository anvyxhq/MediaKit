//
//  SwiftUICropper.swift
//  CropKit
//
//  Created by AnhPT on 03/07/2026.
//

import SwiftUI
import UIKit

/// Owns a ``CropperView`` and exposes crop actions to SwiftUI.
@MainActor
public final class CropController: ObservableObject {
    public let cropperView: CropperView

    @Published public private(set) var canUndo = false
    @Published public private(set) var canRedo = false

    public init(image: UIImage, configuration: CropConfiguration = .init()) {
        cropperView = CropperView(image: image, configuration: configuration)
        cropperView.onChange = { [weak self] in self?.syncUndoState() }
    }

    private func syncUndoState() {
        canUndo = cropperView.canUndo
        canRedo = cropperView.canRedo
    }

    public func undo() { cropperView.undo() }
    public func redo() { cropperView.redo() }

    public func setAspectRatio(_ ratio: CropAspectRatio) { cropperView.setAspectRatio(ratio) }
    public func setShape(_ shape: CropShape) { cropperView.setShape(shape) }
    public func rotate90() { cropperView.rotate90() }
    public func flip(horizontally: Bool = true) { cropperView.flip(horizontally: horizontally) }
    public func reset() { cropperView.reset() }
    public var rotationAngle: CGFloat {
        get { cropperView.rotationAngle }
        set { cropperView.rotationAngle = newValue }
    }
    public func croppedImage() -> UIImage? { cropperView.croppedImage() }
    /// Off-main crop (keeps the UI responsive for large images).
    public func croppedImageAsync() async -> UIImage? { await cropperView.croppedImageAsync() }
    public func cropState() -> CropState { cropperView.cropState() }
    public func restore(_ state: CropState) { cropperView.restore(state) }

    public var colorFilter: ColorFilter {
        get { cropperView.colorFilter }
        set { cropperView.setColorFilter(newValue) }
    }
    public var filterIntensity: CGFloat {
        get { cropperView.filterIntensity }
        set { cropperView.setFilterIntensity(newValue) }
    }
    public var adjustments: ImageAdjustments {
        get { cropperView.adjustments }
        set { cropperView.setAdjustments(newValue) }
    }
    /// Call at the start of a slider drag so the whole drag is one undo step.
    public func beginAdjustment() { cropperView.beginAdjustment() }
}

/// SwiftUI host for the interactive cropper.
///
/// ```swift
/// @StateObject private var crop = CropController(image: photo)
/// var body: some View {
///     ImageCropperView(controller: crop)
///     Button("Crop") { let result = crop.croppedImage() }
/// }
/// ```
public struct ImageCropperView: UIViewRepresentable {
    @ObservedObject private var controller: CropController

    public init(controller: CropController) { self.controller = controller }

    public func makeUIView(context: Context) -> CropperView { controller.cropperView }
    public func updateUIView(_ uiView: CropperView, context: Context) {}
}

/// SwiftUI wrapper for the fine-rotation dial.
public struct RotationDial: UIViewRepresentable {
    @Binding private var angle: CGFloat
    public init(angle: Binding<CGFloat>) { _angle = angle }

    public func makeUIView(context: Context) -> RotationDialView {
        let dial = RotationDialView()
        dial.onChange = { context.coordinator.update($0) }
        return dial
    }
    public func updateUIView(_ uiView: RotationDialView, context: Context) {
        context.coordinator.binding = $angle
    }
    public func makeCoordinator() -> Coordinator { Coordinator(binding: $angle) }

    public final class Coordinator {
        var binding: Binding<CGFloat>
        init(binding: Binding<CGFloat>) { self.binding = binding }
        func update(_ value: CGFloat) { binding.wrappedValue = value }
    }
}

/// SwiftUI wrapper for the circular plate dial.
public struct RotationDialPlate: UIViewRepresentable {
    @Binding private var angle: CGFloat
    public init(angle: Binding<CGFloat>) { _angle = angle }

    public func makeUIView(context: Context) -> RotationDialPlateView {
        let dial = RotationDialPlateView()
        dial.onChange = { context.coordinator.update($0) }
        return dial
    }
    public func updateUIView(_ uiView: RotationDialPlateView, context: Context) {
        context.coordinator.binding = $angle
    }
    public func makeCoordinator() -> Coordinator { Coordinator(binding: $angle) }

    public final class Coordinator {
        var binding: Binding<CGFloat>
        init(binding: Binding<CGFloat>) { self.binding = binding }
        func update(_ value: CGFloat) { binding.wrappedValue = value }
    }
}
