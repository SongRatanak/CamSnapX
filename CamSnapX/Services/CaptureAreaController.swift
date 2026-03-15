//
//  CaptureAreaController.swift
//  CamSnapX
//
//  Created by SongRatanak on 13/3/26.
//

import AppKit
import CoreGraphics
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers
import Vision

final class CaptureAreaController: NSObject {
    static let shared = CaptureAreaController()

    private var previewWindows: [NSPanel] = []
    private var lastCapturedRect: CGRect?

    var hasPreviousArea: Bool {
        lastCapturedRect != nil
    }

    func startCapture() {
        startSystemCapture(arguments: ["-i", "-c"])
    }

    func capturePreviousArea() {
        guard let rect = lastCapturedRect else { return }
        Task { [weak self] in
            await self?.captureAndShow(rect: rect)
        }
    }

    func captureFullScreen() {
        startSystemCapture(arguments: ["-c"])
    }

    func captureWindow() {
        startSystemCapture(arguments: ["-i", "-w", "-c"])
    }

    func showPreview(for fileURL: URL) {
        guard let image = NSImage(contentsOf: fileURL) else { return }
        let screen = screenForPoint(NSEvent.mouseLocation)
        showPreview(with: image, fileURL: fileURL, on: screen)
    }

    func showPreviewForImage(_ image: NSImage) {
        let screen = screenForPoint(NSEvent.mouseLocation)
        showPreviewForImage(image, screen: screen)
    }

    private func startSystemCapture(arguments: [String]) {
        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        process.terminationHandler = { [weak self] process in
            guard process.terminationStatus == 0 else { return }
            DispatchQueue.main.async {
                guard pasteboard.changeCount != initialChangeCount else { return }
                self?.handleClipboardCapture()
            }
        }

        do {
            try process.run()
        } catch {
            showCaptureError(error)
        }
    }


    @MainActor
    func captureAndShow(rect: CGRect) async {
        let unionRect = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let captureRect = rect.intersection(unionRect)
        guard captureRect.width > 2, captureRect.height > 2 else { return }
        if let image = await captureWithScreenCaptureKit(rect: captureRect) {
            showPreviewForImage(image, screen: screenForRect(captureRect))
            return
        }

        if let image = captureWithScreencapture(rect: captureRect) {
            showPreviewForImage(image, screen: screenForRect(captureRect))
            return
        }

        let error = NSError(domain: "CamSnapX", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unable to capture the selected area."])
        showCaptureError(error)
    }

    @MainActor
    func capturePreviewImage(rect: CGRect) async -> NSImage? {
        guard let cgImage = await capturePreviewCGImage(rect: rect) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: rect.width, height: rect.height))
    }

    @MainActor
    func capturePreviewCGImage(rect: CGRect) async -> CGImage? {
        let unionRect = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let captureRect = rect.intersection(unionRect)
        guard captureRect.width > 2, captureRect.height > 2 else { return nil }
        do {
            let displayRect = displaySpaceRect(from: captureRect)
            return try await SCScreenshotManager.captureImage(in: displayRect)
        } catch {
            return nil
        }
    }

    @MainActor
    func captureAndRecognizeText(rect: CGRect) async {
        let unionRect = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let captureRect = rect.intersection(unionRect)
        guard captureRect.width > 2, captureRect.height > 2 else { return }

        let image = await captureWithScreenCaptureKit(rect: captureRect) ?? captureWithScreencapture(rect: captureRect)
        guard let image else {
            showOCRError(message: "Unable to capture the selected area.")
            return
        }

        let recognizedText = await recognizeText(in: image)
        guard let recognizedText, !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showOCRError(message: "No text found in the selected area.")
            return
        }

        copyTextToPasteboard(recognizedText)
    }

    @MainActor
    private func captureWithScreenCaptureKit(rect: CGRect) async -> NSImage? {
        do {
            let displayRect = displaySpaceRect(from: rect)
            let cgImage = try await SCScreenshotManager.captureImage(in: displayRect)
            return NSImage(cgImage: cgImage, size: NSSize(width: rect.width, height: rect.height))
        } catch {
            return nil
        }
    }

    private func captureWithScreencapture(rect: CGRect) -> NSImage? {
        let unionRect = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let captureRect = rect.intersection(unionRect)
        guard captureRect.width > 2, captureRect.height > 2 else { return nil }
        let displayRect = displaySpaceRect(from: captureRect)

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("CamSnapX_capture_\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        let x = Int(displayRect.origin.x.rounded())
        let y = Int(displayRect.origin.y.rounded())
        let w = Int(displayRect.size.width.rounded())
        let h = Int(displayRect.size.height.rounded())
        process.arguments = ["-x", "-R", "\(x),\(y),\(w),\(h)", tempURL.path]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let image = NSImage(contentsOf: tempURL)
        try? FileManager.default.removeItem(at: tempURL)
        return image
    }

    private func handleClipboardCapture() {
        let pasteboard = NSPasteboard.general
        guard let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
              let image = images.first else {
            return
        }

        let screen = screenForPoint(NSEvent.mouseLocation)
        showPreviewForImage(image, screen: screen)
    }

    private func showPreviewForImage(_ image: NSImage, screen: NSScreen?) {
        CaptureHistoryPanelController.shared.hide()
        let fileURL = saveImageToDisk(image)
        showPreview(with: image, fileURL: fileURL, on: screen)
    }

    private func displaySpaceRect(from cocoaRect: CGRect) -> CGRect {
        // Primary screen (index 0) always has origin {0,0} and defines the CG coordinate reference
        let primaryHeight = NSScreen.screens.first?.frame.height ?? cocoaRect.height
        // X is the same in both coordinate systems; only Y needs flipping relative to primary screen height
        return CGRect(
            x: cocoaRect.origin.x,
            y: primaryHeight - cocoaRect.origin.y - cocoaRect.height,
            width: cocoaRect.width,
            height: cocoaRect.height
        )
    }


    private func nextScreenshotURL() -> URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        let folder = (pictures ?? URL(fileURLWithPath: NSHomeDirectory())).appendingPathComponent("CamSnapX", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "CamSnapX_\(formatter.string(from: Date())).png"
        return folder.appendingPathComponent(name)
    }

    private func nextDesktopScreenshotURL() -> URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        let folder = desktop ?? URL(fileURLWithPath: NSHomeDirectory())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "CamSnapX_\(formatter.string(from: Date())).png"
        return folder.appendingPathComponent(name)
    }


    private func saveImageToDisk(_ image: NSImage) -> URL? {
        let fileURL = nextScreenshotURL()
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            try pngData.write(to: fileURL)
            CaptureHistoryStore.shared.add(fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    private func saveImageToDesktop(image: NSImage, fileURL: URL?) -> URL? {
        let destinationURL = nextDesktopScreenshotURL()
        return saveImage(image: image, fileURL: fileURL, to: destinationURL)
    }

    private func saveImage(image: NSImage, fileURL: URL?, to destinationURL: URL) -> URL? {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                CaptureHistoryStore.shared.add(destinationURL)
                print("Saved capture to Desktop:", destinationURL.path)
                return destinationURL
            } catch {
                // Fall back to writing PNG data below.
            }
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            try pngData.write(to: destinationURL, options: .atomic)
            CaptureHistoryStore.shared.add(destinationURL)
            print("Saved capture to Desktop:", destinationURL.path)
            return destinationURL
        } catch {
            print("Failed to save capture to Desktop:", destinationURL.path, error)
            return nil
        }
    }


    private func showPreview(with image: NSImage, fileURL: URL?, on screen: NSScreen?) {
        guard let screen else { return }

        let size = NSSize(width: 232, height: 152)
        let padding: CGFloat = 16
        let spacing: CGFloat = 12
        let stackIndex = previewWindows.count
        let stackedOffset = CGFloat(stackIndex) * (size.height + spacing)
        let origin = NSPoint(
            x: screen.visibleFrame.minX + padding,
            y: screen.visibleFrame.minY + padding + stackedOffset
        )

        let panel = PreviewPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let preview = CapturePreviewView(
            image: image,
            fileURL: fileURL,
            onClose: { [weak self] in
                panel.orderOut(nil)
                self?.previewWindows.removeAll { $0 == panel }
            },
            onCopy: { [weak self] in
                self?.copyToPasteboard(image: image, fileURL: fileURL)
            },
            onSave: { [weak self] in
                return self?.saveImageToDesktop(image: image, fileURL: fileURL) != nil
            }
        )

        panel.contentView = NSHostingView(rootView: preview)
        panel.makeKeyAndOrderFront(nil)

        previewWindows.append(panel)
    }

    private func screenForRect(_ rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

    private func screenForPoint(_ point: CGPoint) -> NSScreen? {
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private func copyToPasteboard(image: NSImage, fileURL: URL?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        let pngData = pngData(from: image)
        let resolvedFileURL = fileURL ?? (pngData.flatMap { writeTemporaryPNG($0, filename: copyFilename()) })

        if let resolvedFileURL {
            item.setString(resolvedFileURL.absoluteString, forType: .fileURL)
        }

        if let pngData {
            item.setData(pngData, forType: .png)
        }

        pasteboard.writeObjects([item])
    }

    private func copyTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func writeTemporaryPNG(_ data: Data, filename: String) -> URL? {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func copyFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd HH.mm.ss"
        let timestamp = formatter.string(from: Date())
        return "CamSnapX \(timestamp).png"
    }

    @MainActor
    private func showCaptureError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Screen Capture Failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor
    private func showOCRError(message: String) {
        let alert = NSAlert()
        alert.messageText = "Text Capture Failed"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func recognizeText(in image: NSImage) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    continuation.resume(returning: nil)
                    return
                }

                let request = VNRecognizeTextRequest { request, _ in
                    guard let results = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let strings = results.compactMap { $0.topCandidates(1).first?.string }
                    let combined = strings.joined(separator: "\n")
                    continuation.resume(returning: combined)
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

}
