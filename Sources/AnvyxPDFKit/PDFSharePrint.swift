//
//  PDFSharePrint.swift
//  PDFKitWrapper
//
//  Created by AnhPT on 03/07/2026.
//

import PDFKit
import UIKit

public extension PDFDocument {
    /// Write the PDF to a temporary file and return its URL (for share / print /
    /// SwiftUI `ShareLink(item:)`). Returns `nil` on failure.
    func temporaryFileURL(named name: String = "document.pdf") -> URL? {
        guard let data = dataRepresentation() else { return nil }
        // Unique subdirectory keeps a clean file name while avoiding collisions
        // between concurrent shares.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

/// Share and print helpers (UIKit entry points).
@MainActor
public enum PDFSharePrint {

    /// Present the system share sheet for `document`.
    public static func share(_ document: PDFDocument,
                             from viewController: UIViewController,
                             fileName: String = "document.pdf") {
        guard let url = document.temporaryFileURL(named: fileName) else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = viewController.view
        activity.popoverPresentationController?.sourceRect = CGRect(
            x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
        viewController.present(activity, animated: true)
    }

    /// Present the system print panel for `document`.
    public static func print(_ document: PDFDocument, jobName: String = "Document") {
        guard let data = document.dataRepresentation() else { return }
        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = jobName
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true, completionHandler: nil)
    }
}
