//
//  CropEditor.swift
//  CropKit
//
//  Created by AnhPT on 03/07/2026.
//

import SwiftUI

/// A ready-to-use SwiftUI crop screen: interactive cropper + toolbar (aspect,
/// shape, filter, rotate, flip, reset), a fine-rotation dial, an adjustments
/// panel (brightness/contrast/saturation/temperature/tint/vibrance + filter
/// strength), and undo/redo.
/// The CropKit equivalent of Mantis's `CropViewController`, SwiftUI-native and accessible.
public struct CropEditor: View {
    @State private var controller: CropController
    @State private var angle: CGFloat = 0
    @State private var showAdjust = false

    @State private var brightness: Float = 0
    @State private var contrast: Float = 1
    @State private var saturation: Float = 1
    @State private var temperature: Float = 6500
    @State private var tint: Float = 0
    @State private var vibrance: Float = 0
    @State private var intensity: CGFloat = 1

    private let configuration: CropConfiguration
    private let onDone: (UIImage?) -> Void
    private let onCancel: () -> Void

    public init(image: UIImage,
                configuration: CropConfiguration = .init(),
                onDone: @escaping (UIImage?) -> Void,
                onCancel: @escaping () -> Void = {}) {
        _controller = State(initialValue: CropController(image: image, configuration: configuration))
        self.configuration = configuration
        self.onDone = onDone
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            ImageCropperView(controller: controller).background(Color.black)

            if configuration.allowsRotation {
                Group {
                    switch configuration.dialStyle {
                    case .ruler: RotationDial(angle: $angle).frame(height: 44)
                    case .plate: RotationDialPlate(angle: $angle).frame(height: 120)
                    }
                }
                .background(Color.black)
                .onChange(of: angle) { _, newValue in controller.rotationAngle = newValue }
                .accessibilityLabel("Rotation angle")
            }

            if showAdjust { adjustPanel.background(.ultraThinMaterial) }
            toolbar.padding(.vertical, 10).background(.ultraThinMaterial)
        }
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: - Adjust panel

    private var adjustPanel: some View {
        VStack(spacing: 8) {
            slider("Brightness", value: $brightness, range: -0.5...0.5, reset: 0) {
                controller.adjustments = current()
            }
            slider("Contrast", value: $contrast, range: 0.5...1.5, reset: 1) {
                controller.adjustments = current()
            }
            slider("Saturation", value: $saturation, range: 0...2, reset: 1) {
                controller.adjustments = current()
            }
            slider("Temperature", value: $temperature, range: 3000...9000, reset: 6500) {
                controller.adjustments = current()
            }
            slider("Tint", value: $tint, range: -50...50, reset: 0) {
                controller.adjustments = current()
            }
            slider("Vibrance", value: $vibrance, range: -1...1, reset: 0) {
                controller.adjustments = current()
            }
            HStack {
                Text("Filter").frame(width: 90, alignment: .leading).font(.caption)
                Slider(value: $intensity, in: 0...1) { editing in
                    if editing { controller.beginAdjustment() } else { controller.filterIntensity = intensity }
                }
                .onChange(of: intensity) { _, v in controller.filterIntensity = v }
                .accessibilityLabel("Filter strength")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }

    private func current() -> ImageAdjustments {
        ImageAdjustments(brightness: brightness, contrast: contrast, saturation: saturation,
                         temperature: temperature, tint: tint, vibrance: vibrance)
    }

    private func slider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>,
                        reset: Float, _ apply: @escaping () -> Void) -> some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading).font(.caption)
            Slider(value: value, in: range) { editing in
                if editing { controller.beginAdjustment() } else { apply() }
            }
            .onChange(of: value.wrappedValue) { _, _ in apply() }
            .accessibilityLabel(title)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 18) {
            button("xmark", "Cancel") { onCancel() }
            button("arrow.uturn.backward", "Undo") { controller.undo() }.disabled(!controller.canUndo)
            button("arrow.uturn.forward", "Redo") { controller.redo() }.disabled(!controller.canRedo)

            Menu {
                ForEach(CropAspectRatio.presets, id: \.label) { r in
                    button(r.label) { controller.setAspectRatio(r) }
                }
            } label: { icon("aspectratio") }.accessibilityLabel("Aspect ratio")

            Menu {
                button("Rectangle") { controller.setShape(.rectangle) }
                button("Ellipse") { controller.setShape(.ellipse) }
                button("Rounded") { controller.setShape(.roundedRect(cornerRadius: 24)) }
            } label: { icon("square.on.circle") }.accessibilityLabel("Crop shape")

            Menu {
                ForEach(ColorFilter.allCases, id: \.self) { f in
                    button(f.displayName) { controller.colorFilter = f }
                }
            } label: { icon("camera.filters") }.accessibilityLabel("Color filter")

            button("slider.horizontal.3", "Adjustments") { showAdjust.toggle() }
            button("rotate.left", "Rotate 90 degrees") { controller.rotate90() }
            button("arrow.left.and.right", "Flip") { controller.flip(horizontally: true) }
            button("arrow.counterclockwise", "Reset") { angle = 0; reset() }

            Spacer(minLength: 0)
            button("checkmark", "Done") { Task { onDone(await controller.croppedImageAsync()) } }
        }
        .padding(.horizontal, 18)
        .font(.system(size: 17, weight: .semibold))
    }

    private func reset() {
        brightness = 0; contrast = 1; saturation = 1; intensity = 1
        temperature = 6500; tint = 0; vibrance = 0
        controller.reset()
    }

    private func icon(_ system: String) -> some View {
        Image(systemName: system).font(.system(size: 17, weight: .semibold))
    }
    private func button(_ system: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { icon(system) }.accessibilityLabel(label)
    }
    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
    }
}
