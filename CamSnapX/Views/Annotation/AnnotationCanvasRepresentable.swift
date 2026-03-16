//
//  AnnotationCanvasRepresentable.swift
//  CamSnapX
//
//  Created by SongRatanak on 15/3/26.
//

import SwiftUI

struct AnnotationCanvasRepresentable: NSViewRepresentable {
    @Binding var image: NSImage
    @ObservedObject var state: AnnotationState
    /// Callback: (imagePoint, viewPoint, imageToViewScale) for new text
    var onRequestTextEditor: ((CGPoint, CGPoint, CGFloat) -> Void)?
    /// Callback: (annotationID, currentText, viewPoint, imageToViewScale) for editing existing text
    var onRequestEditTextAnnotation: ((UUID, String, CGPoint, CGFloat) -> Void)?
    /// Hide this annotation from drawing while editing in-place
    var editingAnnotationID: UUID?

    func makeNSView(context: Context) -> AnnotationCanvasView {
        let canvas = AnnotationCanvasView(image: image, annotationState: state)
        canvas.onRequestTextEditor = onRequestTextEditor
        canvas.onRequestEditTextAnnotation = onRequestEditTextAnnotation
        canvas.editingAnnotationID = editingAnnotationID
        canvas.onImageCropped = { newImage in
            DispatchQueue.main.async {
                self.image = newImage
            }
        }
        return canvas
    }

    func updateNSView(_ nsView: AnnotationCanvasView, context: Context) {
        nsView.image = image
        nsView.annotationState = state
        nsView.onRequestTextEditor = onRequestTextEditor
        nsView.onRequestEditTextAnnotation = onRequestEditTextAnnotation
        nsView.editingAnnotationID = editingAnnotationID
        nsView.onImageCropped = { newImage in
            DispatchQueue.main.async {
                self.image = newImage
            }
        }
        nsView.needsDisplay = true
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}
