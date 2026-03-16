//
//  ImageViewerController.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class ImageViewerController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let image: NSImage
    private let fileURL: URL?
    private let annotationState = AnnotationState()

    init(image: NSImage, fileURL: URL?) {
        self.image = image
        self.fileURL = fileURL
        super.init()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let imageSize = image.size
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let maxWidth = screen.visibleFrame.width * 0.8
        let maxHeight = screen.visibleFrame.height * 0.8

        // Scale image to fit screen, wider to accommodate toolbar
        var windowWidth = imageSize.width
        var windowHeight = imageSize.height
        if windowWidth > maxWidth || windowHeight > maxHeight {
            let scale = min(maxWidth / windowWidth, maxHeight / windowHeight)
            windowWidth *= scale
            windowHeight *= scale
        }
        windowWidth = max(windowWidth, 700)
        windowHeight = max(windowHeight, 400)

        let contentView = ImageViewerView(
            image: image,
            fileURL: fileURL,
            annotationState: annotationState,
            onDone: { [weak self] in self?.close() },
            onSaveAs: { [weak self] annotatedImage in self?.saveAs(annotatedImage: annotatedImage) }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = fileURL?.lastPathComponent ?? "CamSnapX Preview"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 500, height: 300)
        window.contentView = NSHostingView(rootView: contentView)
        window.center()

        // Show in Dock
        NSApp.setActivationPolicy(.regular)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func close() {
        window?.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
        ImageViewerController.activeViewers.removeAll { $0 === self }
    }

    // MARK: - Save As

    private func saveAs(annotatedImage: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "CamSnapX Capture.png"
        panel.canCreateDirectories = true

        guard let parentWindow = window else { return }
        panel.beginSheetModal(for: parentWindow) { response in
            guard response == .OK, let url = panel.url else { return }
            guard let tiffData = annotatedImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
            try? pngData.write(to: url, options: .atomic)
        }
    }

    // Keep active viewers alive
    static var activeViewers: [ImageViewerController] = []
}

// MARK: - SwiftUI View

struct ImageViewerView: View {
    @State var image: NSImage
    let fileURL: URL?
    @ObservedObject var annotationState: AnnotationState
    let onDone: () -> Void
    let onSaveAs: (NSImage) -> Void

    @State private var isEditingText = false
    @State private var textEditImagePoint: CGPoint = .zero
    @State private var textEditPosition: CGPoint = .zero
    @State private var textEditContent: String = ""
    @State private var textEditFontSize: CGFloat = 20
    @State private var textEditColor: NSColor? = nil  // nil = use toolbar color
    @State private var textEditStyle: TextAnnotationStyle = .standard
    @State private var imageToViewScale: CGFloat = 1.0
    @State private var editingAnnotationID: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Annotation toolbar
            AnnotationToolbarView(
                state: annotationState,
                onSaveAs: {
                    let rendered = AnnotationRenderer.render(
                        annotations: annotationState.annotations,
                        onto: image
                    )
                    onSaveAs(rendered)
                },
                onDone: onDone
            )

            Divider()

            // Canvas with image + annotations
            ZStack(alignment: .topLeading) {
                AnnotationCanvasRepresentable(
                    image: $image,
                    state: annotationState,
                    onRequestTextEditor: { imagePoint, viewPoint, scale in
                        editingAnnotationID = nil
                        textEditImagePoint = imagePoint
                        textEditPosition = viewPoint
                        textEditContent = ""
                        textEditColor = nil
                        textEditStyle = annotationState.textStyle
                        imageToViewScale = scale
                        textEditFontSize = annotationState.fontSize
                        isEditingText = true
                    },
                    onRequestEditTextAnnotation: { annotationID, currentText, viewPoint, scale in
                        editingAnnotationID = annotationID
                        textEditPosition = viewPoint
                        textEditContent = currentText
                        imageToViewScale = scale
                        if let ann = annotationState.annotations.first(where: { $0.id == annotationID }) {
                            textEditFontSize = ann.fontSize * scale
                            textEditColor = ann.color
                            textEditStyle = ann.textStyle
                        }
                        isEditingText = true
                    },
                    editingAnnotationID: editingAnnotationID
                )

                // Click-outside overlay to commit text
                if isEditingText {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            commitTextAnnotation()
                        }
                }

                // Text editing overlay — uses .position() internally
                if isEditingText {
                    AnnotationTextEditor(
                        text: $textEditContent,
                        nsColor: textEditColor ?? annotationState.selectedColor,
                        onCommit: {
                            commitTextAnnotation()
                        },
                        onCancel: {
                            isEditingText = false
                            textEditContent = ""
                            textEditColor = nil
                            editingAnnotationID = nil
                        },
                        position: $textEditPosition,
                        fontSize: $textEditFontSize,
                        textStyle: textEditStyle
                    )
                }
            }
        }
        .onChange(of: annotationState.selectedTool) {
            if isEditingText {
                commitTextAnnotation()
            }
        }
    }

    private func commitTextAnnotation() {
        if textEditContent.isEmpty {
            if let existingID = editingAnnotationID {
                annotationState.annotations.removeAll { $0.id == existingID }
                if annotationState.selectedAnnotationID == existingID {
                    annotationState.selectedAnnotationID = nil
                }
                annotationState.onStateChanged?()
            }
            isEditingText = false
            editingAnnotationID = nil
            return
        }

        // Convert view-space font size to image-space
        let imageFontSize = imageToViewScale > 0 ? textEditFontSize / imageToViewScale : textEditFontSize

        if let existingID = editingAnnotationID,
           let idx = annotationState.annotations.firstIndex(where: { $0.id == existingID }) {
            // Update existing text annotation
            annotationState.annotations[idx].text = textEditContent
            annotationState.annotations[idx].fontSize = imageFontSize
            annotationState.onStateChanged?()
        } else {
            // Create new text annotation
            var annotation = Annotation(
                tool: .text,
                color: annotationState.selectedColor,
                fontSize: imageFontSize,
                textStyle: textEditStyle
            )
            annotation.boundingRect = CGRect(origin: textEditImagePoint, size: .zero)
            annotation.text = textEditContent
            annotationState.addAnnotation(annotation)
        }

        isEditingText = false
        textEditContent = ""
        textEditColor = nil
        editingAnnotationID = nil
    }
}
