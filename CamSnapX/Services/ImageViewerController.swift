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
    var onImageUpdated: ((NSImage) -> Void)?
    private var hasUnsavedChanges = false
    private var commitPendingEdits: (() -> Void)?
    private var isClosingWithConfirmation = false

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
        windowWidth = max(windowWidth, 980)
        windowHeight = max(windowHeight, 400)

        let contentView = ImageViewerView(
            image: image,
            fileURL: fileURL,
            annotationState: annotationState,
            onDone: { [weak self] in self?.close() },
            onDidModify: { [weak self] in self?.hasUnsavedChanges = true },
            onRegisterCommitHandler: { [weak self] handler in
                self?.commitPendingEdits = handler
            },
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
        window.minSize = NSSize(width: 980, height: 300)
        window.contentView = NSHostingView(rootView: contentView)
        window.center()

        // Show in Dock
        NSApp.setActivationPolicy(.regular)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func close() {
        if !annotationState.annotations.isEmpty {
            let rendered = AnnotationRenderer.render(
                annotations: annotationState.annotations,
                onto: image
            )
            if let fileURL {
                overwriteImage(rendered, at: fileURL)
                CaptureHistoryStore.shared.refresh(fileURL)
            }
        onImageUpdated?(rendered)
    }
    hasUnsavedChanges = false
    window?.close()
}

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
        ImageViewerController.activeViewers.removeAll { $0 === self }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard hasUnsavedChanges, !isClosingWithConfirmation else { return true }

        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes you made to the screenshot?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            commitPendingEdits?()
            isClosingWithConfirmation = true
            close()
            return false
        case .alertSecondButtonReturn:
            isClosingWithConfirmation = true
            sender.close()
            return false
        default:
            return false
        }
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
            self.writePNG(annotatedImage, to: url)
        }
    }

    private func overwriteImage(_ image: NSImage, at url: URL) {
        writePNG(image, to: url)
    }

    private func writePNG(_ image: NSImage, to url: URL) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        try? pngData.write(to: url, options: .atomic)
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
    let onDidModify: () -> Void
    let onRegisterCommitHandler: (@escaping () -> Void) -> Void
    let onSaveAs: (NSImage) -> Void

    @State private var isEditingText = false
    @State private var textEditImagePoint: CGPoint = .zero
    @State private var textEditPosition: CGPoint = .zero
    @State private var textEditInitialViewPosition: CGPoint = .zero  // To compute move delta
    @State private var textEditContent: String = ""
    @State private var textEditFontSize: CGFloat = 20
    @State private var textEditColor: NSColor? = nil  // nil = use toolbar color
    @State private var textEditStyle: TextAnnotationStyle = .standard
    @State private var textEditBoxWidth: CGFloat? = nil
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
                onDone: handleDone
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
                        textEditInitialViewPosition = viewPoint
                        textEditContent = ""
                        textEditColor = nil
                        textEditStyle = annotationState.textStyle
                        imageToViewScale = scale
                        textEditFontSize = annotationState.fontSize * scale
                        textEditBoxWidth = nil
                        isEditingText = true
                    },
                    onRequestEditTextAnnotation: { annotationID, currentText, viewPoint, scale in
                        editingAnnotationID = annotationID
                        textEditPosition = viewPoint
                        textEditInitialViewPosition = viewPoint
                        textEditContent = currentText
                        imageToViewScale = scale
                        if let ann = annotationState.annotations.first(where: { $0.id == annotationID }) {
                            textEditImagePoint = ann.boundingRect.origin
                            textEditFontSize = ann.fontSize * scale
                            textEditColor = ann.color
                            textEditStyle = ann.textStyle
                            if let w = ann.textBoxWidth {
                                textEditBoxWidth = w * scale
                            } else {
                                textEditBoxWidth = nil
                            }
                            annotationState.fontSize = ann.fontSize
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
                        .allowsHitTesting(true)
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
                            textEditBoxWidth = nil
                            editingAnnotationID = nil
                        },
                        position: $textEditPosition,
                        fontSize: $textEditFontSize,
                        textStyle: textEditStyle,
                        boxWidth: $textEditBoxWidth,
                        imageToViewScale: imageToViewScale
                    )
                    .allowsHitTesting(true)
                }
            }
        }
        .onChange(of: annotationState.selectedTool) {
            if isEditingText {
                commitTextAnnotation()
            }
        }
        .onChange(of: textEditFontSize) { newValue in
            guard isEditingText else { return }
            let imageFontSize = imageToViewScale > 0 ? newValue / imageToViewScale : newValue
            annotationState.fontSize = imageFontSize
        }
        .onChange(of: annotationState.fontSize) { newValue in
            guard isEditingText else { return }
            let viewFontSize = imageToViewScale > 0 ? newValue * imageToViewScale : newValue
            if abs(textEditFontSize - viewFontSize) > 0.5 {
                textEditFontSize = viewFontSize
            }
        }
        .onChange(of: annotationState.textStyle) { newValue in
            if isEditingText {
                textEditStyle = newValue
            } else if let selectedID = annotationState.selectedAnnotationID,
                      let idx = annotationState.annotations.firstIndex(where: { $0.id == selectedID }),
                      annotationState.annotations[idx].tool == .text {
                annotationState.annotations[idx].textStyle = newValue
                annotationState.onStateChanged?()
            }
        }
        .onChange(of: annotationState.selectedColor) { newValue in
            if isEditingText {
                textEditColor = newValue
            } else if let selectedID = annotationState.selectedAnnotationID,
                      let idx = annotationState.annotations.firstIndex(where: { $0.id == selectedID }),
                      annotationState.annotations[idx].tool == .text {
                annotationState.annotations[idx].color = newValue
                annotationState.onStateChanged?()
            }
        }
        .onChange(of: annotationState.annotations.map(\.id)) { _ in
            onDidModify()
        }
        .onChange(of: annotationState.activeAnnotation?.id) { _ in
            onDidModify()
        }
        .onChange(of: textEditContent) { _ in
            if isEditingText {
                onDidModify()
            }
        }
        .onAppear {
            onRegisterCommitHandler {
                commitPendingEdits()
            }
        }
    }

    private func handleDone() {
        commitPendingEdits()
        onDone()
    }

    private func commitPendingEdits() {
        if isEditingText {
            commitTextAnnotation()
        }
        if annotationState.activeAnnotation != nil {
            annotationState.commitActiveAnnotation()
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
        let imageBoxWidth = (textEditBoxWidth ?? 0) > 0 && imageToViewScale > 0
            ? textEditBoxWidth! / imageToViewScale
            : nil

        // Compute final image-space origin from any move delta during editing
        let finalImagePoint: CGPoint
        if imageToViewScale > 0 {
            let deltaX = (textEditPosition.x - textEditInitialViewPosition.x) / imageToViewScale
            let deltaY = (textEditPosition.y - textEditInitialViewPosition.y) / imageToViewScale
            finalImagePoint = CGPoint(
                x: textEditImagePoint.x + deltaX,
                y: textEditImagePoint.y + deltaY
            )
        } else {
            finalImagePoint = textEditImagePoint
        }

        if let existingID = editingAnnotationID,
           let idx = annotationState.annotations.firstIndex(where: { $0.id == existingID }) {
            // Update existing text annotation
            annotationState.annotations[idx].text = textEditContent
            annotationState.annotations[idx].fontSize = imageFontSize
            annotationState.annotations[idx].textBoxWidth = imageBoxWidth
            annotationState.annotations[idx].boundingRect.origin = finalImagePoint
            annotationState.onStateChanged?()
        } else {
            // Create new text annotation
            var annotation = Annotation(
                tool: .text,
                color: annotationState.selectedColor,
                fontSize: imageFontSize,
                textStyle: textEditStyle,
                textBoxWidth: imageBoxWidth
            )
            annotation.boundingRect = CGRect(origin: finalImagePoint, size: .zero)
            annotation.text = textEditContent
            annotationState.addAnnotation(annotation)
        }

        isEditingText = false
        textEditContent = ""
        textEditColor = nil
        textEditBoxWidth = nil
        editingAnnotationID = nil
    }
}
