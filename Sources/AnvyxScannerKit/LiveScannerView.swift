//
//  LiveScannerView.swift
//  ScannerKit
//
//  Created by AnhPT on 13/07/2026.
//

import SwiftUI
import AVFoundation
import AnvyxCameraKit

/// A ready-to-use live scanner screen: camera preview + live document-frame or
/// text-underline overlay + a shutter. In document mode the shutter returns every
/// detected document, perspective-corrected; in text mode it returns the photo.
///
/// ```swift
/// LiveScannerView(mode: .document, maximumDocuments: 3) { pages in
///     self.captured = pages          // [UIImage] → feed to AnvyxDocProcessingKit
/// } onCancel: { dismiss() }
/// ```
public struct LiveScannerView: View {
    @State private var scanner: LiveScanner
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    @Environment(\.scenePhase) private var scenePhase
    private let onCapture: ([UIImage]) -> Void
    private let onCancel: () -> Void

    public init(
        mode: LiveScanner.Mode = .document,
        autoCapture: Bool = false,
        maximumDocuments: Int = 3,
        onCapture: @escaping ([UIImage]) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        _scanner = State(initialValue: LiveScanner(mode: mode, autoCapture: autoCapture, maximumDocuments: maximumDocuments))
        self.onCapture = onCapture
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            CameraPreview(session: scanner.camera.session) { layer in
                DispatchQueue.main.async { previewLayer = layer }
            }
            .ignoresSafeArea()
            ScannerOverlay(quads: scanner.quads, textLines: scanner.textLines,
                           contentAspect: scanner.frameAspect, previewLayer: previewLayer)
                .ignoresSafeArea()

            VStack {
                HStack {
                    button("xmark", "Cancel") { onCancel() }
                    Spacer()
                    Picker("Mode", selection: $scanner.mode) {
                        Text("Multi").tag(LiveScanner.Mode.document)
                        Text("Single").tag(LiveScanner.Mode.singleDocument)
                        Text("Text").tag(LiveScanner.Mode.text)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    Spacer()
                    button(scanner.autoCaptureEnabled ? "bolt.fill" : "bolt.slash",
                           scanner.autoCaptureEnabled ? "Auto-capture on" : "Auto-capture off") {
                        scanner.autoCaptureEnabled.toggle()
                    }
                    .foregroundStyle(scanner.autoCaptureEnabled ? .yellow : .white)
                }
                .padding()

                Text(scanner.guidance.message)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)

                Spacer()

                Button {
                    Task { onCapture(await scanner.capture()) }
                } label: {
                    Circle().fill(.white)
                        .frame(width: 70, height: 70)
                        .overlay(Circle().stroke(.white, lineWidth: 4).padding(4))
                }
                .padding(.bottom, 30)
                .accessibilityLabel("Capture")
            }
            .foregroundStyle(.white)
        }
        .background(Color.black)
        .task {
            scanner.onAutoCapture = onCapture   // auto-captured pages use the same handler
            await scanner.start()
        }
        .onDisappear { scanner.stop() }
        .onChange(of: scenePhase) { _, phase in
            // Pause the camera + Vision when backgrounded; resume when active.
            switch phase {
            case .active: Task { await scanner.start() }
            default: scanner.stop()
            }
        }
    }

    private func button(_ system: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 20, weight: .semibold))
        }
        .accessibilityLabel(label)
    }
}
