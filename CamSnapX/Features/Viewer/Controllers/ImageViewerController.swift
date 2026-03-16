//
//  ImageViewerController.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

final class ImageState: ObservableObject {
    @Published var image: NSImage

    init(image: NSImage) {
        self.image = image
    }
}

final class ImageViewerController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let imageState: ImageState
    private let fileURL: URL?
    private let annotationState = AnnotationState()
    var onImageUpdated: ((NSImage) -> Void)?
    private var hasUnsavedChanges = false
    private var commitPendingEdits: (() -> Void)?
    private var isClosingWithConfirmation = false

    init(image: NSImage, fileURL: URL?) {
        self.imageState = ImageState(image: image)
        self.fileURL = fileURL
        super.init()
    }

    @MainActor
    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        loadAnnotationSnapshotIfNeeded()

        let imageSize = imageState.image.size
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
            imageState: imageState,
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
        commitPendingEdits?()

        let baseImage = imageState.image
        let rendered = AnnotationRenderer.render(
            annotations: annotationState.annotations,
            onto: baseImage
        )

        if let fileURL {
            overwriteImage(rendered, at: fileURL)
            CaptureHistoryStore.shared.refresh(fileURL)
            saveAnnotationSnapshot(baseImage: baseImage, annotations: annotationState.annotations, to: fileURL)
        }

        onImageUpdated?(rendered)
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
            let baseImage = self.imageState.image
            self.saveAnnotationSnapshot(baseImage: baseImage, annotations: self.annotationState.annotations, to: url)
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

    @MainActor
    private func loadAnnotationSnapshotIfNeeded() {
        guard let fileURL else { return }
        let sidecarURL = annotationSidecarURL(for: fileURL)
        guard let data = try? Data(contentsOf: sidecarURL) else { return }
        let decoder = JSONDecoder()
        guard let snapshot = try? decoder.decode(AnnotationSnapshot.self, from: data) else { return }
        guard let baseImage = NSImage(data: snapshot.baseImagePNG) else { return }

        imageState.image = baseImage
        annotationState.annotations = snapshot.annotations.map { $0.toAnnotation() }
    }

    private func saveAnnotationSnapshot(baseImage: NSImage, annotations: [Annotation], to fileURL: URL) {
        let sidecarURL = annotationSidecarURL(for: fileURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let snapshot = AnnotationSnapshot(baseImage: baseImage, annotations: annotations)
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: sidecarURL, options: .atomic)
    }

    private func annotationSidecarURL(for fileURL: URL) -> URL {
        fileURL.appendingPathExtension("annotations.json")
    }

    // Keep active viewers alive
    static var activeViewers: [ImageViewerController] = []
}

// MARK: - Persistence Models

private struct AnnotationSnapshot: Codable {
    let baseImagePNG: Data
    let annotations: [AnnotationRecord]

    init(baseImage: NSImage, annotations: [Annotation]) {
        self.baseImagePNG = AnnotationSnapshot.pngData(from: baseImage)
        self.annotations = annotations.map { AnnotationRecord(from: $0) }
    }

    private static func pngData(from image: NSImage) -> Data {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return Data()
        }
        return pngData
    }
}

private struct AnnotationRecord: Codable {
    let id: UUID
    let tool: String
    let color: ColorRecord
    let lineWidth: CGFloat
    let arrowStyle: String?
    let curveControlPoint: PointRecord?
    let points: [PointRecord]
    let boundingRect: RectRecord
    let text: String
    let fontSize: CGFloat
    let textStyle: String
    let textBoxWidth: CGFloat?
    let isComplete: Bool

    init(from annotation: Annotation) {
        id = annotation.id
        tool = annotation.tool.rawValue
        color = ColorRecord(from: annotation.color)
        lineWidth = annotation.lineWidth
        arrowStyle = annotation.arrowStyle.rawValue
        curveControlPoint = annotation.curveControlPoint.map(PointRecord.init)
        points = annotation.points.map(PointRecord.init)
        boundingRect = RectRecord(from: annotation.boundingRect)
        text = annotation.text
        fontSize = annotation.fontSize
        textStyle = annotation.textStyle.rawValue
        textBoxWidth = annotation.textBoxWidth
        isComplete = annotation.isComplete
    }

    func toAnnotation() -> Annotation {
        var annotation = Annotation(
            id: id,
            tool: AnnotationTool(rawValue: tool) ?? .arrow,
            color: color.toColor(),
            lineWidth: lineWidth,
            arrowStyle: ArrowAnnotationStyle(rawValue: arrowStyle ?? "") ?? .standard,
            curveControlPoint: curveControlPoint?.toPoint(),
            points: points.map { $0.toPoint() },
            boundingRect: boundingRect.toRect(),
            text: text,
            fontSize: fontSize,
            textStyle: TextAnnotationStyle(rawValue: textStyle) ?? .standard,
            textBoxWidth: textBoxWidth
        )
        annotation.isComplete = isComplete
        return annotation
    }
}

private struct PointRecord: Codable {
    let x: CGFloat
    let y: CGFloat

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    func toPoint() -> CGPoint {
        CGPoint(x: x, y: y)
    }
}

private struct RectRecord: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(from rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    func toRect() -> CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

private struct ColorRecord: Codable {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let a: CGFloat

    init(from color: NSColor) {
        let converted = color.usingColorSpace(.sRGB) ?? color
        r = converted.redComponent
        g = converted.greenComponent
        b = converted.blueComponent
        a = converted.alphaComponent
    }

    func toColor() -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - SwiftUI View

struct ImageViewerView: View {
    @ObservedObject var imageState: ImageState
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
                        onto: imageState.image
                    )
                    onSaveAs(rendered)
                },
                onDone: handleDone
            )

            Divider()

            // Canvas with image + annotations
            ScrollView([.vertical, .horizontal]) {
                ZStack(alignment: .topLeading) {
                    AnnotationCanvasRepresentable(
                        image: $imageState.image,
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
                .frame(width: imageState.image.size.width, height: imageState.image.size.height)
            }
        }
        .onChange(of: annotationState.selectedTool) {
            if isEditingText {
                commitTextAnnotation()
            }
        }
        .onChange(of: annotationState.selectedAnnotationID) { _ in
            guard let selectedID = annotationState.selectedAnnotationID,
                  let idx = annotationState.annotations.firstIndex(where: { $0.id == selectedID }) else { return }
            let selected = annotationState.annotations[idx]
            switch selected.tool {
            case .arrow:
                annotationState.selectedTool = .arrow
                annotationState.lineWidth = selected.lineWidth
                annotationState.arrowStyle = selected.arrowStyle
            case .line, .rectangle, .filledRectangle, .circle:
                annotationState.selectedTool = selected.tool
                annotationState.lineWidth = selected.lineWidth
            default:
                break
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
        .onChange(of: annotationState.arrowStyle) { newValue in
            guard let selectedID = annotationState.selectedAnnotationID,
                  let idx = annotationState.annotations.firstIndex(where: { $0.id == selectedID }),
                  annotationState.annotations[idx].tool == .arrow else { return }
            annotationState.annotations[idx].arrowStyle = newValue
            annotationState.onStateChanged?()
        }
        .onChange(of: annotationState.lineWidth) { newValue in
            guard let selectedID = annotationState.selectedAnnotationID,
                  let idx = annotationState.annotations.firstIndex(where: { $0.id == selectedID }) else { return }
            let tool = annotationState.annotations[idx].tool
            if tool == .arrow || tool == .line || tool == .rectangle || tool == .filledRectangle || tool == .circle {
                annotationState.annotations[idx].lineWidth = newValue
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
